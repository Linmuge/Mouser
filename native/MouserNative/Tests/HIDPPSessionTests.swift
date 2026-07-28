import Foundation
import Testing
@testable import MouserNative

private actor ScriptedHIDPPTransport: HIDPPReportTransport {
    private let scriptedReports: [[UInt8]]
    private let finishes: Bool
    private(set) var sentReports: [[UInt8]] = []

    init(scriptedReports: [[UInt8]], finishes: Bool = true) {
        self.scriptedReports = scriptedReports
        self.finishes = finishes
    }

    func reports() -> AsyncThrowingStream<[UInt8], any Error> {
        let reports = scriptedReports
        let finishes = finishes
        return AsyncThrowingStream { continuation in
            for report in reports {
                continuation.yield(report)
            }
            if finishes {
                continuation.finish()
            }
        }
    }

    func send(_ report: [UInt8]) {
        sentReports.append(report)
    }
}

private actor SimulatedHIDPPRequester: HIDPPRequesting {
    let featureIndexes: [UInt8: [HIDPPFeature: UInt8]]
    let names: [UInt8: String]
    private(set) var requestedDeviceIndexes: [UInt8] = []

    init(featureIndexes: [UInt8: [HIDPPFeature: UInt8]], names: [UInt8: String]) {
        self.featureIndexes = featureIndexes
        self.names = names
    }

    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration
    ) async throws -> HIDPPResponse {
        requestedDeviceIndexes.append(deviceIndex)
        if command.featureIndex == 0x00, command.parameters.count >= 2 {
            let raw = UInt16(command.parameters[0]) << 8 | UInt16(command.parameters[1])
            let feature = HIDPPFeature(rawValue: raw)
            let index = feature.flatMap { featureIndexes[deviceIndex]?[$0] } ?? 0
            return response(deviceIndex: deviceIndex, featureIndex: 0x00, parameters: [index])
        }

        guard let nameFeature = featureIndexes[deviceIndex]?[.deviceName],
              command.featureIndex == nameFeature,
              let name = names[deviceIndex]
        else {
            throw HIDPPSessionError.deviceError(0x06)
        }
        if command.function == 0x00 {
            return response(
                deviceIndex: deviceIndex,
                featureIndex: nameFeature,
                parameters: [UInt8(name.utf8.count)]
            )
        }
        let offset = Int(command.parameters.first ?? 0)
        return response(
            deviceIndex: deviceIndex,
            featureIndex: nameFeature,
            parameters: Array(name.utf8.dropFirst(offset).prefix(16))
        )
    }

    private func response(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        parameters: [UInt8]
    ) -> HIDPPResponse {
        HIDPPResponse(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            function: 0x01,
            softwareID: HIDPPCodec.softwareID,
            parameters: parameters
        )
    }
}

@Suite("HID++ request session")
struct HIDPPSessionTests {
    @Test("input report IDs are restored only when callback data omits them")
    func normalizesInputReports() {
        #expect(
            HIDReportNormalizer.inputBytes(
                reportID: 0x11,
                data: [0x01, 0x05, 0x4A, 0x00]
            ) == [0x11, 0x01, 0x05, 0x4A, 0x00]
        )
        #expect(
            HIDReportNormalizer.inputBytes(
                reportID: 0x11,
                data: [0x11, 0x01, 0x05, 0x4A, 0x00]
            ) == [0x11, 0x01, 0x05, 0x4A, 0x00]
        )
    }

    @Test("IOKit output payload retains the report identifier")
    func retainsIOKitOutputReportID() throws {
        let report = try HIDPPCodec.encodeRequest(
            deviceIndex: 0x01,
            featureIndex: 0x00,
            function: 0x00,
            parameters: [0x1B, 0x04, 0x00]
        )

        #expect(IOKitReportNormalizer.outputBytes(for: report) == report)
    }

    @Test("request sends one long report and ignores unrelated input")
    func requestMatchesItsResponse() async throws {
        let transport = ScriptedHIDPPTransport(scriptedReports: [
            [0x11, 0x01, 0x06, 0x1A, 0x99],
            [0x11, 0x01, 0x05, 0x4A, 0x00, 0x06, 0x40],
        ])
        let session = HIDPPSession(transport: transport)
        let command = HIDPPCommand(
            featureIndex: 0x05,
            function: 0x03,
            parameters: [0x00, 0x06, 0x40]
        )

        let response = try await session.request(
            command,
            deviceIndex: 0x01,
            timeout: .seconds(1)
        )

        #expect(response.parameters == [0x00, 0x06, 0x40])
        let sent = await transport.sentReports
        #expect(sent.count == 1)
        #expect(Array(sent[0].prefix(7)) == [0x11, 0x01, 0x05, 0x3A, 0x00, 0x06, 0x40])
    }

    @Test("a session ignores a delayed response from another software identifier")
    func ignoresDelayedResponseFromAnotherSession() async throws {
        let transport = ScriptedHIDPPTransport(scriptedReports: [
            [0x11, 0x01, 0x05, 0x4A, 0x50, 0x00, 0x00],
            [0x11, 0x01, 0x05, 0x43, 0x00, 0x06, 0x40],
        ])
        let session = HIDPPSession(transport: transport, softwareID: 0x03)

        let response = try await session.request(
            HIDPPCommand(featureIndex: 0x05, function: 0x03, parameters: [0x00]),
            deviceIndex: 0x01,
            timeout: .seconds(1)
        )

        #expect(response.parameters == [0x00, 0x06, 0x40])
        let sent = await transport.sentReports
        #expect(sent[0][3] == 0x33)
    }

    @Test("matching HID++ error responses surface their device error code")
    func requestSurfacesDeviceError() async {
        let transport = ScriptedHIDPPTransport(scriptedReports: [
            [0x11, 0x01, 0xFF, 0x0A, 0x05, 0x07],
        ])
        let session = HIDPPSession(transport: transport)

        await #expect(throws: HIDPPSessionError.deviceError(0x07)) {
            try await session.request(
                HIDPPCommand(featureIndex: 0x05, function: 0x03, parameters: []),
                deviceIndex: 0x01,
                timeout: .seconds(1)
            )
        }
    }

    @Test("requests stop at their deadline when no response arrives")
    func requestTimesOut() async {
        let transport = ScriptedHIDPPTransport(scriptedReports: [], finishes: false)
        let session = HIDPPSession(transport: transport)

        await #expect(throws: HIDPPSessionError.timeout) {
            try await session.request(
                HIDPPCommand(featureIndex: 0x00, function: 0x00, parameters: [0x1B, 0x04, 0]),
                deviceIndex: 0x01,
                timeout: .milliseconds(20)
            )
        }
    }

    @Test("unsolicited reports are exposed as decoded event responses")
    func streamsDecodedEvents() async throws {
        let transport = ScriptedHIDPPTransport(scriptedReports: [
            [0x11, 0x01, 0x05, 0x00, 0x00, 0xC4, 0x00, 0x00],
            [0x01, 0x02],
        ])
        let session = HIDPPSession(transport: transport)
        let stream = try await session.events()
        var responses: [HIDPPResponse] = []

        for try await response in stream {
            responses.append(response)
        }

        #expect(responses.count == 1)
        #expect(responses[0].featureIndex == 0x05)
        #expect(responses[0].softwareID == 0)
        #expect(responses[0].parameters.prefix(4) == [0x00, 0xC4, 0x00, 0x00])
    }

    @Test("receiver probing skips empty slots and returns the HID++ device identity")
    func probesReceiverSlots() async throws {
        let requester = SimulatedHIDPPRequester(
            featureIndexes: [
                0x01: [:],
                0x02: [
                    .reprogrammableControlsV4: 0x05,
                    .deviceName: 0x08,
                    .adjustableDPI: 0x09,
                    .smartShiftEnhanced: 0x0A,
                    .unifiedBattery: 0x0B,
                ],
            ],
            names: [0x02: "MX Master 3S"]
        )
        let probe = HIDPPDeviceProbe(requester: requester)

        let identity = try #require(await probe.firstDevice(in: [0x01, 0x02, 0x03]))

        #expect(identity.deviceIndex == 0x02)
        #expect(identity.name == "MX Master 3S")
        #expect(identity.featureIndexes[.reprogrammableControlsV4] == 0x05)
        #expect(identity.featureIndexes[.adjustableDPI] == 0x09)
        #expect(identity.featureIndexes[.smartShiftEnhanced] == 0x0A)
        let indexes = await requester.requestedDeviceIndexes
        #expect(indexes.first == 0x01)
        #expect(indexes.contains(0x02))
        #expect(!indexes.contains(0x03))
    }
}
