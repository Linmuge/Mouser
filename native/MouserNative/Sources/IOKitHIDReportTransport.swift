import Foundation
import IOKit.hid

enum IOKitHIDReportTransportError: LocalizedError {
    case invalidReport
    case managerOpen(IOReturn)
    case deviceNotFound
    case deviceOpen(IOReturn)
    case setReport(IOReturn)

    var errorDescription: String? {
        switch self {
        case .invalidReport:
            "HID++ report is empty"
        case let .managerOpen(code):
            "IOHIDManagerOpen failed: 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .deviceNotFound:
            "The matching Logitech HID++ interface is unavailable"
        case let .deviceOpen(code):
            "IOHIDDeviceOpen failed: 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case let .setReport(code):
            "IOHIDDeviceSetReport failed: 0x\(String(UInt32(bitPattern: code), radix: 16))"
        }
    }
}

enum IOKitReportNormalizer {
    static func outputBytes(for report: [UInt8]) -> [UInt8] { report }
}

enum IOKitHIDDeviceMatcher {
    static func matchingDictionary(for device: LogitechHIDDevice) -> [String: Any] {
        var matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x046D,
            kIOHIDProductIDKey: Int(device.productID),
            kIOHIDPrimaryUsagePageKey: Int(device.usagePage),
        ]
        if let usage = device.usage {
            matching[kIOHIDPrimaryUsageKey] = Int(usage)
        }
        if let locationID = device.locationID, locationID <= UInt64(Int.max) {
            matching[kIOHIDLocationIDKey] = Int(locationID)
        }
        return matching
    }
}

private final class IOKitReportInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [
        UUID: AsyncThrowingStream<[UInt8], any Error>.Continuation
    ] = [:]
    private var terminalError: (any Error)?
    private var isFinished = false

    func stream() -> AsyncThrowingStream<[UInt8], any Error> {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [UInt8].self,
            throwing: (any Error).self,
            bufferingPolicy: .bufferingNewest(64)
        )
        continuation.onTermination = { [weak self] _ in self?.remove(id) }

        lock.lock()
        if isFinished {
            let error = terminalError
            lock.unlock()
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        } else {
            continuations[id] = continuation
            lock.unlock()
        }
        return stream
    }

    func yield(_ report: [UInt8]) {
        lock.lock()
        let current = Array(continuations.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(report)
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        terminalError = error
        let current = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in current {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

private func iokitInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    reportType: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard result == kIOReturnSuccess,
          reportLength > 0,
          let context
    else { return }
    let inbox = Unmanaged<IOKitReportInbox>.fromOpaque(context).takeUnretainedValue()
    inbox.yield(
        HIDReportNormalizer.inputBytes(
            reportID: UInt8(exactly: reportID),
            data: Array(UnsafeBufferPointer(start: report, count: reportLength))
        )
    )
}

private func iokitRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let inbox = Unmanaged<IOKitReportInbox>.fromOpaque(context).takeUnretainedValue()
    inbox.finish(throwing: HIDPPSessionError.responseStreamEnded)
}

private final class IOKitHIDDeviceSession: @unchecked Sendable {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private let callbackQueue = DispatchQueue(label: "io.github.tombadash.mouser.iokit-hid")
    private let cancellationSemaphore = DispatchSemaphore(value: 0)
    private let inbox = IOKitReportInbox()
    private let closeLock = NSLock()
    private var isClosed = false

    init(device descriptor: LogitechHIDDevice) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            IOKitHIDDeviceMatcher.matchingDictionary(for: descriptor) as CFDictionary
        )
        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw IOKitHIDReportTransportError.managerOpen(managerResult)
        }
        guard let device = Self.firstDevice(in: manager) else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw IOKitHIDReportTransportError.deviceNotFound
        }
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw IOKitHIDReportTransportError.deviceOpen(deviceResult)
        }

        self.manager = manager
        self.device = device
        inputBuffer = .allocate(capacity: 64)
        inputBuffer.initialize(repeating: 0, count: 64)

        let context = Unmanaged.passUnretained(inbox).toOpaque()
        IOHIDDeviceSetDispatchQueue(device, callbackQueue)
        IOHIDDeviceSetCancelHandler(device) { [cancellationSemaphore] in
            cancellationSemaphore.signal()
        }
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputBuffer,
            64,
            iokitInputReportCallback,
            context
        )
        IOHIDDeviceRegisterRemovalCallback(device, iokitRemovalCallback, context)
        IOHIDDeviceActivate(device)
    }

    deinit {
        close()
        inputBuffer.deinitialize(count: 64)
        inputBuffer.deallocate()
    }

    func reports() -> AsyncThrowingStream<[UInt8], any Error> { inbox.stream() }

    func send(_ report: [UInt8]) throws {
        guard let reportID = report.first else {
            throw IOKitHIDReportTransportError.invalidReport
        }
        let bytes = IOKitReportNormalizer.outputBytes(for: report)
        let result = bytes.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(reportID),
                buffer.baseAddress!,
                buffer.count
            )
        }
        guard result == kIOReturnSuccess else {
            throw IOKitHIDReportTransportError.setReport(result)
        }
    }

    private func close() {
        closeLock.lock()
        guard !isClosed else {
            closeLock.unlock()
            return
        }
        isClosed = true
        closeLock.unlock()

        inbox.finish()
        IOHIDDeviceCancel(device)
        _ = cancellationSemaphore.wait(timeout: .now() + 2)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private static func firstDevice(in manager: IOHIDManager) -> IOHIDDevice? {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return nil }
        let count = CFSetGetCount(devices)
        guard count > 0 else { return nil }
        var values = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(devices, &values)
        guard let value = values.first ?? nil else { return nil }
        return unsafeBitCast(value, to: IOHIDDevice.self)
    }
}

actor IOKitHIDReportTransport: HIDPPReportTransport {
    private let session: IOKitHIDDeviceSession

    init(device: LogitechHIDDevice) throws {
        session = try IOKitHIDDeviceSession(device: device)
    }

    func reports() -> AsyncThrowingStream<[UInt8], any Error> {
        session.reports()
    }

    func send(_ report: [UInt8]) throws {
        try session.send(report)
    }
}
