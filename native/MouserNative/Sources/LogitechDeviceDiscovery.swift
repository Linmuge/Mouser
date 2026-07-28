import CoreHID
import Foundation
import IOKit.hid

struct LogitechHIDDevice: Identifiable, Equatable, Sendable {
    let id: UInt64
    let productID: UInt32
    let productName: String?
    let transport: String
    let usagePage: UInt16
    let usage: UInt16?
    let locationID: UInt64?

    init(
        id: UInt64,
        productID: UInt32,
        productName: String?,
        transport: String,
        usagePage: UInt16 = 0,
        usage: UInt16? = nil,
        locationID: UInt64? = nil
    ) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.transport = transport
        self.usagePage = usagePage
        self.usage = usage
        self.locationID = locationID
    }

    var catalogName: String? {
        switch productID {
        case 0xB034, 0xB043: "MX Master 3S"
        case 0xB042, 0xB048: "MX Master 4"
        default: nil
        }
    }

    var isReceiver: Bool {
        productID == 0xC52B || productID == 0xC548
    }

    var isMouse: Bool {
        if catalogName != nil { return true }
        let normalizedName = productName?.lowercased() ?? ""
        return normalizedName.contains("mouse") || normalizedName.contains("mx master")
    }

    var isHIDPPInterface: Bool { usagePage >= 0xFF00 }

    var displayName: String {
        if let catalogName { return catalogName }
        if isReceiver { return "Logitech USB Receiver" }
        return productName?.nonEmpty ?? "Logitech HID 0x\(String(productID, radix: 16, uppercase: true))"
    }
}

protocol LogitechDeviceDiscovering: Sendable {
    func updates() -> AsyncStream<[LogitechHIDDevice]>
    func identify(_ device: LogitechHIDDevice) async -> HIDPPDeviceIdentity?
    func controller(
        for device: LogitechHIDDevice,
        identity: HIDPPDeviceIdentity
    ) async -> (any HIDPPDeviceControlling)?
}

extension LogitechDeviceDiscovering {
    func controller(
        for device: LogitechHIDDevice,
        identity: HIDPPDeviceIdentity
    ) async -> (any HIDPPDeviceControlling)? {
        nil
    }
}

enum LogitechDeviceInventory {
    static func preferredHIDPPInterface(
        from devices: [LogitechHIDDevice]
    ) -> LogitechHIDDevice? {
        devices
            .filter(\.isHIDPPInterface)
            .sorted { lhs, rhs in
                if lhs.isReceiver != rhs.isReceiver { return lhs.isReceiver }
                return lhs.id < rhs.id
            }
            .first
    }
}

enum IOKitLogitechDeviceSnapshot {
    static func current() -> [LogitechHIDDevice] {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(
            manager,
            [kIOHIDVendorIDKey: 0x046D] as CFDictionary
        )

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return [] }
        return devices.compactMap(snapshot).sorted { $0.id < $1.id }
    }

    private static func snapshot(_ device: IOHIDDevice) -> LogitechHIDDevice? {
        guard numberProperty(kIOHIDVendorIDKey, of: device) == 0x046D,
              let productID = numberProperty(kIOHIDProductIDKey, of: device)
        else { return nil }

        var registryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != 0,
              IORegistryEntryGetRegistryEntryID(service, &registryID) == kIOReturnSuccess
        else { return nil }

        return LogitechHIDDevice(
            id: registryID,
            productID: UInt32(truncatingIfNeeded: productID),
            productName: stringProperty(kIOHIDProductKey, of: device),
            transport: stringProperty(kIOHIDTransportKey, of: device) ?? "未知连接",
            usagePage: UInt16(truncatingIfNeeded: numberProperty(kIOHIDPrimaryUsagePageKey, of: device) ?? 0),
            usage: numberProperty(kIOHIDPrimaryUsageKey, of: device).map(UInt16.init(truncatingIfNeeded:)),
            locationID: numberProperty(kIOHIDLocationIDKey, of: device).map(UInt64.init)
        )
    }

    private static func numberProperty(_ key: String, of device: IOHIDDevice) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func stringProperty(_ key: String, of device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}

actor CoreHIDLogitechDeviceDiscovery: LogitechDeviceDiscovering {
    typealias NotificationSource = @Sendable (
        [HIDDeviceManager.DeviceMatchingCriteria]
    ) async -> AsyncThrowingStream<HIDDeviceManager.Notification, any Error>
    typealias SnapshotSource = @Sendable () async -> [LogitechHIDDevice]

    private let notificationSource: NotificationSource
    private let snapshotSource: SnapshotSource
    private let retryDelay: Duration
    private var deviceReferences: [UInt64: HIDDeviceClient.DeviceReference] = [:]
    private var nextSoftwareID = UInt8(
        ProcessInfo.processInfo.processIdentifier % 15 + 1
    )

    init() {
        let manager = HIDDeviceManager()
        notificationSource = { criteria in
            await manager.monitorNotifications(matchingCriteria: criteria)
        }
        snapshotSource = { IOKitLogitechDeviceSnapshot.current() }
        retryDelay = .seconds(1)
    }

    init(
        notificationSource: @escaping NotificationSource,
        retryDelay: Duration,
        snapshotSource: @escaping SnapshotSource = { [] }
    ) {
        self.notificationSource = notificationSource
        self.retryDelay = retryDelay
        self.snapshotSource = snapshotSource
    }

    nonisolated func updates() -> AsyncStream<[LogitechHIDDevice]> {
        AsyncStream { continuation in
            let monitorTask = Task {
                await monitor(continuation: continuation)
            }
            continuation.onTermination = { _ in
                monitorTask.cancel()
            }
        }
    }

    private func monitor(
        continuation: AsyncStream<[LogitechHIDDevice]>.Continuation
    ) async {
        var devices = Dictionary(
            uniqueKeysWithValues: await snapshotSource().map { ($0.id, $0) }
        )
        if !devices.isEmpty {
            continuation.yield(devices.values.sorted { $0.id < $1.id })
        }
        let criteria = HIDDeviceManager.DeviceMatchingCriteria(vendorID: 0x046D)

        while !Task.isCancelled {
            do {
                let notifications = await notificationSource([criteria])
                for try await notification in notifications {
                    guard !Task.isCancelled else { break }
                    switch notification {
                    case let .deviceMatched(reference):
                        deviceReferences[reference.deviceID] = reference
                        if let device = await snapshot(for: reference) {
                            devices[reference.deviceID] = device
                        }
                    case let .deviceRemoved(reference):
                        deviceReferences.removeValue(forKey: reference.deviceID)
                        devices.removeValue(forKey: reference.deviceID)
                    @unknown default:
                        continue
                    }
                    continuation.yield(devices.values.sorted { $0.id < $1.id })
                }
            } catch is CancellationError {
                break
            } catch {
                // Lock, sleep, USB reset, and receiver reconnects can terminate
                // CoreHID's stream. Clear stale state and subscribe again.
            }

            guard !Task.isCancelled else { break }
            deviceReferences.removeAll()
            devices = Dictionary(
                uniqueKeysWithValues: await snapshotSource().map { ($0.id, $0) }
            )
            continuation.yield(devices.values.sorted { $0.id < $1.id })
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                break
            }
        }
        continuation.finish()
    }

    private func snapshot(
        for reference: HIDDeviceClient.DeviceReference
    ) async -> LogitechHIDDevice? {
        guard let client = HIDDeviceClient(deviceReference: reference),
              await client.vendorID == 0x046D
        else { return nil }

        let primaryUsage = await client.primaryUsage
        return LogitechHIDDevice(
            id: reference.deviceID,
            productID: await client.productID,
            productName: await client.product,
            transport: Self.displayName(for: await client.transport),
            usagePage: primaryUsage.page,
            usage: primaryUsage.usage,
            locationID: await client.locationID
        )
    }

    func identify(_ device: LogitechHIDDevice) async -> HIDPPDeviceIdentity? {
        guard device.isHIDPPInterface else { return nil }

        guard let transport = try? IOKitHIDReportTransport(device: device) else {
            return nil
        }
        let session = HIDPPSession(
            transport: transport,
            softwareID: allocateSoftwareID()
        )
        let probe = HIDPPDeviceProbe(requester: session)
        return await probe.firstDevice(
            in: Self.deviceIndexes(for: device),
            timeout: .milliseconds(450)
        )
    }

    func diagnosticFeatureProbe(_ device: LogitechHIDDevice) async -> [String] {
        guard device.isHIDPPInterface,
              let transport = try? IOKitHIDReportTransport(device: device)
        else { return ["IOKit interface unavailable"] }
        let session = HIDPPSession(
            transport: transport,
            softwareID: allocateSoftwareID()
        )
        var lines: [String] = []
        for index in Self.deviceIndexes(for: device) {
            do {
                let response = try await session.request(
                    HIDPPCommands.discover(.reprogrammableControlsV4),
                    deviceIndex: index,
                    timeout: .milliseconds(600)
                )
                let bytes = response.parameters
                    .map { String(format: "%02X", $0) }
                    .joined(separator: " ")
                lines.append("slot \(index): \(bytes)")
            } catch {
                lines.append("slot \(index): \(String(describing: error))")
            }
        }
        return lines
    }

    func controller(
        for device: LogitechHIDDevice,
        identity: HIDPPDeviceIdentity
    ) async -> (any HIDPPDeviceControlling)? {
        guard device.isHIDPPInterface,
              let transport = try? IOKitHIDReportTransport(device: device)
        else { return nil }
        let session = HIDPPSession(
            transport: transport,
            softwareID: allocateSoftwareID()
        )
        return HIDPPDeviceController(requester: session, identity: identity)
    }

    private func allocateSoftwareID() -> UInt8 {
        let allocated = nextSoftwareID
        nextSoftwareID = allocated == 0x0F ? 0x01 : allocated + 1
        return allocated
    }

    private static func deviceIndexes(for device: LogitechHIDDevice) -> [UInt8] {
        if device.isReceiver {
            return device.productID == 0xC548
                ? Array(1...6)
                : [0xFF] + Array(1...6)
        }
        return [0xFF]
    }

    private static func displayName(for transport: HIDDeviceTransport?) -> String {
        switch transport {
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .bluetoothLowEnergy: "Bluetooth Low Energy"
        case .bluetoothAACP: "Bluetooth AACP"
        case .aid: "AID"
        case .i2c: "I²C"
        case .spi: "SPI"
        case .serial: "Serial"
        case .iap: "iAP"
        case .airPlay: "AirPlay"
        case .spu: "SPU"
        case .fifo: "FIFO"
        case .inductiveInBand: "Inductive In-Band"
        case .virtual: "Virtual"
        case let .unknown(value): value
        case nil: "未知连接"
        @unknown default: "未知连接"
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
