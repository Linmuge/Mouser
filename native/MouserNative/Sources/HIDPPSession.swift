import Foundation

protocol HIDPPReportTransport: Sendable {
    func reports() async throws -> AsyncThrowingStream<[UInt8], any Error>
    func send(_ report: [UInt8]) async throws
}

protocol HIDPPRequesting: Sendable {
    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration
    ) async throws -> HIDPPResponse
}

protocol HIDPPEventStreaming: Sendable {
    func events() async throws -> AsyncThrowingStream<HIDPPResponse, any Error>
}

enum HIDPPSessionError: Error, Equatable {
    case timeout
    case responseStreamEnded
    case deviceError(UInt8)
}

actor HIDPPSession: HIDPPRequesting, HIDPPEventStreaming {
    private let transport: any HIDPPReportTransport
    private let softwareID: UInt8

    init(
        transport: any HIDPPReportTransport,
        softwareID: UInt8 = HIDPPCodec.softwareID
    ) {
        self.transport = transport
        self.softwareID = softwareID
    }

    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration = .seconds(2)
    ) async throws -> HIDPPResponse {
        let responseStream = try await transport.reports()
        let requestReport = try HIDPPCodec.encodeRequest(
            deviceIndex: deviceIndex,
            featureIndex: command.featureIndex,
            function: command.function,
            parameters: command.parameters,
            softwareID: softwareID
        )
        let responseSoftwareID = softwareID
        try await transport.send(requestReport)

        return try await withThrowingTaskGroup(of: HIDPPResponse.self) { group in
            group.addTask {
                for try await bytes in responseStream {
                    guard let response = try? HIDPPCodec.decodeResponse(bytes),
                          response.deviceIndex == deviceIndex,
                          response.softwareID == responseSoftwareID
                    else { continue }

                    if response.isError,
                       response.parameters.first == command.featureIndex
                    {
                        throw HIDPPSessionError.deviceError(response.errorCode ?? 0)
                    }
                    if HIDPPCodec.matches(
                        response,
                        featureIndex: command.featureIndex,
                        function: command.function,
                        softwareID: responseSoftwareID
                    ) {
                        return response
                    }
                }
                throw HIDPPSessionError.responseStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HIDPPSessionError.timeout
            }

            guard let response = try await group.next() else {
                throw HIDPPSessionError.responseStreamEnded
            }
            group.cancelAll()
            return response
        }
    }

    func events() async throws -> AsyncThrowingStream<HIDPPResponse, any Error> {
        let reports = try await transport.reports()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await bytes in reports {
                        guard !Task.isCancelled else { break }
                        if let response = try? HIDPPCodec.decodeResponse(bytes) {
                            continuation.yield(response)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct HIDPPDeviceIdentity: Equatable, Sendable {
    let deviceIndex: UInt8
    let name: String
    let featureIndexes: [HIDPPFeature: UInt8]
}

struct HIDPPDeviceProbe: Sendable {
    private let requester: any HIDPPRequesting

    init(requester: any HIDPPRequesting) {
        self.requester = requester
    }

    func firstDevice(
        in deviceIndexes: [UInt8],
        timeout: Duration = .milliseconds(450)
    ) async -> HIDPPDeviceIdentity? {
        for deviceIndex in deviceIndexes {
            guard let reprogIndex = await findFeature(
                .reprogrammableControlsV4,
                deviceIndex: deviceIndex,
                timeout: timeout
            ) else { continue }

            var indexes: [HIDPPFeature: UInt8] = [
                .reprogrammableControlsV4: reprogIndex,
            ]
            for feature in Self.optionalFeatures {
                if let index = await findFeature(
                    feature,
                    deviceIndex: deviceIndex,
                    timeout: timeout
                ) {
                    indexes[feature] = index
                }
            }
            let name = await readDeviceName(
                featureIndex: indexes[.deviceName],
                deviceIndex: deviceIndex,
                timeout: timeout
            ) ?? "Logitech HID++ Device"
            return HIDPPDeviceIdentity(
                deviceIndex: deviceIndex,
                name: name,
                featureIndexes: indexes
            )
        }
        return nil
    }

    private func findFeature(
        _ feature: HIDPPFeature,
        deviceIndex: UInt8,
        timeout: Duration
    ) async -> UInt8? {
        do {
            let response = try await requester.request(
                HIDPPCommands.discover(feature),
                deviceIndex: deviceIndex,
                timeout: timeout
            )
            guard let index = response.parameters.first, index != 0 else { return nil }
            return index
        } catch {
            return nil
        }
    }

    private func readDeviceName(
        featureIndex: UInt8?,
        deviceIndex: UInt8,
        timeout: Duration
    ) async -> String? {
        guard let featureIndex,
              let info = try? await requester.request(
                HIDPPCommand(featureIndex: featureIndex, function: 0x00, parameters: [0, 0, 0]),
                deviceIndex: deviceIndex,
                timeout: timeout
              ),
              let length = info.parameters.first,
              length > 0
        else { return nil }

        var bytes: [UInt8] = []
        while bytes.count < Int(length) {
            let offset = UInt8(clamping: bytes.count)
            guard let response = try? await requester.request(
                HIDPPCommand(featureIndex: featureIndex, function: 0x01, parameters: [offset, 0, 0]),
                deviceIndex: deviceIndex,
                timeout: timeout
            ), !response.parameters.isEmpty else { break }
            bytes.append(contentsOf: response.parameters.prefix(Int(length) - bytes.count))
        }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            .nonEmpty
    }

    private static let optionalFeatures: [HIDPPFeature] = [
        .deviceName,
        .adjustableDPI,
        .smartShiftEnhanced,
        .smartShift,
        .highResolutionWheelEnhanced,
        .highResolutionWheel,
        .thumbWheel,
        .unifiedBattery,
        .batteryStatus,
        .haptic,
        .forceSensing,
    ]
}
