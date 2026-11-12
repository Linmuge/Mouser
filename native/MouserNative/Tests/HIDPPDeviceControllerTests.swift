import Foundation
import Testing
@testable import MouserNative

private actor RecordingHIDPPRequester: HIDPPRequesting, HIDPPEventStreaming {
    private var responses: [HIDPPCommand: HIDPPResponse]
    private let eventResponses: [HIDPPResponse]
    private(set) var commands: [HIDPPCommand] = []

    init(
        responses: [HIDPPCommand: HIDPPResponse],
        eventResponses: [HIDPPResponse] = []
    ) {
        self.responses = responses
        self.eventResponses = eventResponses
    }

    func events() -> AsyncThrowingStream<HIDPPResponse, any Error> {
        let eventResponses = eventResponses
        return AsyncThrowingStream { continuation in
            for response in eventResponses { continuation.yield(response) }
            continuation.finish()
        }
    }

    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration
    ) async throws -> HIDPPResponse {
        commands.append(command)
        guard let response = responses[command] else {
            throw HIDPPSessionError.deviceError(0x07)
        }
        return response
    }
}

private actor RestartableHIDPPRequester: HIDPPRequesting, HIDPPEventStreaming {
    private var eventContinuations: [
        AsyncThrowingStream<HIDPPResponse, any Error>.Continuation
    ] = []
    private(set) var commands: [HIDPPCommand] = []

    func events() -> AsyncThrowingStream<HIDPPResponse, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: HIDPPResponse.self,
            throwing: (any Error).self
        )
        eventContinuations.append(continuation)
        return stream
    }

    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration
    ) async throws -> HIDPPResponse {
        commands.append(command)
        return HIDPPResponse(
            deviceIndex: deviceIndex,
            featureIndex: command.featureIndex,
            function: command.function,
            softwareID: HIDPPCodec.softwareID,
            parameters: command.parameters
        )
    }

    func finishEventStream(at index: Int) {
        eventContinuations[index].finish()
    }
}

private actor BlockingSetupHIDPPRequester: HIDPPRequesting, HIDPPEventStreaming {
    private var eventContinuations: [
        AsyncThrowingStream<HIDPPResponse, any Error>.Continuation
    ] = []
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private(set) var commands: [HIDPPCommand] = []

    func events() -> AsyncThrowingStream<HIDPPResponse, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: HIDPPResponse.self,
            throwing: (any Error).self
        )
        eventContinuations.append(continuation)
        return stream
    }

    func request(
        _ command: HIDPPCommand,
        deviceIndex: UInt8,
        timeout: Duration
    ) async throws -> HIDPPResponse {
        _ = timeout
        commands.append(command)
        if commands.count == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }
        return HIDPPResponse(
            deviceIndex: deviceIndex,
            featureIndex: command.featureIndex,
            function: command.function,
            softwareID: HIDPPCodec.softwareID,
            parameters: command.parameters
        )
    }

    func firstRequestIsBlocked() -> Bool { firstRequestContinuation != nil }

    func releaseFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }

    func finishEventStream(at index: Int) {
        eventContinuations[index].finish()
    }
}

@Suite("HID++ device controller")
struct HIDPPDeviceControllerTests {
    @Test("reads every available setting into one partial device snapshot")
    func readsDeviceState() async throws {
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
                .haptic: 0x12,
                .batteryStatus: 0x08,
            ]
        )
        let requester = RecordingHIDPPRequester(responses: [
            HIDPPCommands.readDPI(featureIndex: 0x0C): Self.response(0x0C, [0x00, 0x06, 0x40]),
            HIDPPCommands.readSmartShift(featureIndex: 0x0D, enhanced: false): Self.response(0x0D, [0x02, 25, 0]),
            HIDPPCommands.readWheelMode(featureIndex: 0x0E): Self.response(0x0E, [0x06]),
            HIDPPCommands.readThumbWheelStatus(featureIndex: 0x0F): Self.response(0x0F, [0x00, 0x01]),
            HIDPPCommands.readHapticState(featureIndex: 0x12): Self.response(0x12, [0x01, 75, 0x01]),
            HIDPPCommands.readBattery(featureIndex: 0x08, unified: false): Self.response(0x08, [82, 0, 0]),
        ])
        let controller = HIDPPDeviceController(requester: requester, identity: identity)

        let state = await controller.readState()

        #expect(state.dpi == 1600)
        #expect(
            state.smartShift == HIDPPSmartShiftState(
                mode: .ratchet,
                automatic: true,
                threshold: 25,
                scrollForce: 0
            )
        )
        #expect(state.battery == HIDPPBatteryState(level: 82, charging: false))
        #expect(state.verticalScrollInverted == true)
        #expect(state.horizontalScrollInverted == true)
        #expect(state.haptic == HIDPPHapticState(enabled: true, deviceLevel: 75))
    }

    @Test("vertical inversion performs a read-modify-write and preserves high resolution")
    func writesVerticalInversionSafely() async throws {
        let read = HIDPPCommands.readWheelMode(featureIndex: 0x0E)
        let write = HIDPPCommands.setWheelMode(featureIndex: 0x0E, mode: 0x06)
        let requester = RecordingHIDPPRequester(responses: [
            read: Self.response(0x0E, [0x03]),
            write: Self.response(0x0E, [0x06]),
        ])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.highResolutionWheelEnhanced: 0x0E])
        )

        try await controller.setVerticalScrollInverted(true)

        #expect(await requester.commands == [read, write])
    }

    @Test("DPI SmartShift and thumb wheel writes use discovered feature indexes")
    func writesDeviceSettings() async throws {
        let setDPI = HIDPPCommands.setDPI(featureIndex: 0x0C, dpi: 1600)
        let setSmartShift = HIDPPCommands.setSmartShift(
            featureIndex: 0x0D,
            enhanced: false,
            mode: .ratchet,
            automatic: false,
            threshold: 25,
            scrollForce: 50
        )
        let setThumb = HIDPPCommands.setThumbWheelInverted(featureIndex: 0x0F, inverted: true)
        let requester = RecordingHIDPPRequester(responses: [
            setDPI: Self.response(0x0C, [0x00, 0x06, 0x40]),
            setSmartShift: Self.response(0x0D, [0x02, 0xFF, 0]),
            setThumb: Self.response(0x0F, [0x00, 0x01]),
        ])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .thumbWheel: 0x0F,
            ])
        )

        try await controller.setDPI(1600)
        try await controller.setSmartShift(
            mode: .ratchet,
            automatic: false,
            threshold: 25,
            scrollForce: 50
        )
        try await controller.setHorizontalScrollInverted(true)

        #expect(await requester.commands == [setDPI, setSmartShift, setThumb])
    }

    @Test("unsupported settings fail without sending an unrelated request")
    func rejectsUnsupportedFeatures() async {
        let requester = RecordingHIDPPRequester(responses: [:])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [:])
        )

        await #expect(throws: HIDPPDeviceControlError.unsupportedFeature(.adjustableDPI)) {
            try await controller.setDPI(1600)
        }
        #expect(await requester.commands.isEmpty)
    }

    @Test("haptic level waveform and force sensing use their discovered features")
    func writesHapticAndForceSensing() async throws {
        let setLevel = HIDPPCommands.setHapticLevel(featureIndex: 0x12, level: 3)
        let play = HIDPPCommands.playHapticWaveform(featureIndex: 0x12, waveformID: 7)
        let setForce = HIDPPCommands.setForceSensing(featureIndex: 0x13, value: 420)
        let requester = RecordingHIDPPRequester(responses: [
            setLevel: Self.response(0x12, [0x01, 100]),
            play: Self.response(0x12, [7]),
            setForce: Self.response(0x13, [0x00, 0x01, 0xA4]),
        ])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.haptic: 0x12, .forceSensing: 0x13])
        )

        try await controller.setHapticLevel(3)
        try await controller.playHapticWaveform(7)
        try await controller.setForceSensing(420)

        #expect(await requester.commands == [setLevel, play, setForce])
    }

    @Test("force sensing capabilities and current value are decoded")
    func readsForceSensingState() async {
        let count = HIDPPCommands.readForceSensingCount(featureIndex: 0x13)
        let configuration = HIDPPCommands.readForceSensingConfiguration(featureIndex: 0x13)
        let current = HIDPPCommands.readForceSensingCurrent(featureIndex: 0x13)
        let requester = RecordingHIDPPRequester(responses: [
            count: Self.response(0x13, [0x01]),
            configuration: Self.response(0x13, [0x00, 0x01, 0x01, 0x2C, 0x03, 0xE8, 0x00, 0x64]),
            current: Self.response(0x13, [0x01, 0x90]),
        ])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.forceSensing: 0x13])
        )

        let state = await controller.readState()

        #expect(
            state.forceSensing == HIDPPForceSensingState(
                minimum: 100,
                maximum: 1000,
                defaultValue: 300,
                currentValue: 400,
                isChangeable: true
            )
        )
    }

    @Test("reprogrammable control inventory decodes CIDs and capability flags")
    func readsReprogrammableControls() async {
        let count = HIDPPCommands.readReprogrammableControlCount(featureIndex: 0x05)
        let first = HIDPPCommands.readReprogrammableControl(featureIndex: 0x05, index: 0)
        let second = HIDPPCommands.readReprogrammableControl(featureIndex: 0x05, index: 1)
        let firstReporting = HIDPPCommands.readCIDReporting(featureIndex: 0x05, cid: 0x01A0)
        let secondReporting = HIDPPCommands.readCIDReporting(featureIndex: 0x05, cid: 0x00FD)
        let requester = RecordingHIDPPRequester(responses: [
            count: Self.response(0x05, [2]),
            first: Self.response(0x05, [0x01, 0xA0, 0, 1, 0x20, 1, 1, 1, 0x01]),
            second: Self.response(0x05, [0x00, 0xFD, 0, 2, 0x20, 2, 1, 1, 0]),
            firstReporting: Self.response(0x05, [0x01, 0xA0, 0x11, 0x01, 0xA0, 0]),
            secondReporting: Self.response(0x05, [0x00, 0xFD, 0x01, 0x00, 0xFD, 0]),
        ])
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )

        let controls = await controller.readReprogrammableControls()

        #expect(controls == [
            HIDPPReprogrammableControl(
                index: 0,
                cid: 0x01A0,
                taskID: 1,
                flags: 0x0120,
                mappingFlags: 0x0011
            ),
            HIDPPReprogrammableControl(
                index: 1,
                cid: 0x00FD,
                taskID: 2,
                flags: 0x0020,
                mappingFlags: 0x0001
            ),
        ])
        #expect(controls[0].isDivertable)
        #expect(controls[0].supportsRawXY)
        #expect(!controls[1].supportsRawXY)

        let reporting = await controller.readSpecialInputReporting(
            for: [.actionsRing, .dpiSwitch]
        )
        #expect(reporting == [
            .actionsRing: HIDPPCIDReportingState(cid: 0x01A0, flags: 0x11),
            .dpiSwitch: HIDPPCIDReportingState(cid: 0x00FD, flags: 0x01),
        ])
    }

    @Test("special buttons are persistently diverted, streamed, and restored")
    func streamsSpecialButtons() async throws {
        let gestureOn = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .divertButton
        )
        let modeOn = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C4,
            mode: .divertButton
        )
        let gestureOff = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .restoreButton
        )
        let modeOff = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C4,
            mode: .restoreButton
        )
        let requester = RecordingHIDPPRequester(
            responses: [
                gestureOn: Self.response(0x05, gestureOn.parameters),
                modeOn: Self.response(0x05, modeOn.parameters),
                gestureOff: Self.response(0x05, gestureOff.parameters),
                modeOff: Self.response(0x05, modeOff.parameters),
            ],
            eventResponses: [
                Self.event(0x05, [0x00, 0xC3, 0x00, 0xC4, 0x00, 0x00]),
                Self.event(0x05, [0x00, 0x00]),
            ]
        )
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )
        let stream = try await controller.specialButtonEvents(
            for: [.gesture, .modeShift],
            timeout: .seconds(1)
        )
        var events: [HIDPPButtonEvent] = []

        for try await event in stream { events.append(event) }

        #expect(events == [
            .init(button: .gesture, isPressed: true),
            .init(button: .modeShift, isPressed: true),
            .init(button: .gesture, isPressed: false),
            .init(button: .modeShift, isPressed: false),
        ])
        #expect(await requester.commands == [gestureOn, modeOn, gestureOff, modeOff])
    }

    @Test("gesture mode requests RawXY and restores both persistent flags")
    func streamsGestureRawXY() async throws {
        let divert = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .divertRawXY
        )
        let restore = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .restoreRawXY
        )
        let requester = RecordingHIDPPRequester(
            responses: [
                divert: Self.response(0x05, divert.parameters),
                restore: Self.response(0x05, restore.parameters),
            ],
            eventResponses: [Self.event(0x05, [0xFF, 0xF6, 0x00, 0x14], function: 1)]
        )
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )
        let stream = try await controller.specialInputEvents(
            for: [.gesture],
            rawXYButtons: [.gesture],
            timeout: .seconds(1)
        )
        var events: [HIDPPSpecialInputEvent] = []

        for try await event in stream { events.append(event) }

        #expect(events == [.movement(dx: -10, dy: 20)])
        #expect(await requester.commands == [divert, restore])
    }

    @Test("a discovered 0x00D7 gesture control is diverted and routed")
    func routesDiscoveredD7GestureControl() async throws {
        let count = HIDPPCommands.readReprogrammableControlCount(featureIndex: 0x05)
        let control = HIDPPCommands.readReprogrammableControl(featureIndex: 0x05, index: 0)
        let reporting = HIDPPCommands.readCIDReporting(featureIndex: 0x05, cid: 0x00D7)
        let divert = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00D7,
            mode: .divertButton
        )
        let restore = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00D7,
            mode: .restoreButton
        )
        let requester = RecordingHIDPPRequester(
            responses: [
                count: Self.response(0x05, [1]),
                control: Self.response(0x05, [0x00, 0xD7, 0, 1, 0x20, 0, 0, 0, 0]),
                reporting: Self.response(0x05, [0x00, 0xD7, 0, 0x00, 0xD7, 0]),
                divert: Self.response(0x05, divert.parameters),
                restore: Self.response(0x05, restore.parameters),
            ],
            eventResponses: [
                Self.event(0x05, [0x00, 0xD7, 0x00, 0x00]),
                Self.event(0x05, [0x00, 0x00]),
            ]
        )
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )

        let controls = await controller.readReprogrammableControls()
        #expect(controls.map(\.cid) == [0x00D7])

        let stream = try await controller.specialButtonEvents(
            for: [.gesture],
            timeout: .seconds(1)
        )
        var events: [HIDPPButtonEvent] = []
        for try await event in stream { events.append(event) }

        #expect(events == [
            .init(button: .gesture, isPressed: true),
            .init(button: .gesture, isPressed: false),
        ])
        #expect(await requester.commands == [count, control, reporting, divert, restore])
    }

    @Test("ending an old special-input stream cannot restore over its replacement")
    func restartDoesNotLetOldStreamRestoreNewDiversion() async throws {
        let divert = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .divertButton
        )
        let restore = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .restoreButton
        )
        let requester = RestartableHIDPPRequester()
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )

        let firstStream = try await controller.specialInputEvents(
            for: [.gesture],
            rawXYButtons: [],
            timeout: .seconds(1)
        )
        let secondStream = try await controller.specialInputEvents(
            for: [.gesture],
            rawXYButtons: [],
            timeout: .seconds(1)
        )
        _ = (firstStream, secondStream)
        #expect(await requester.commands == [divert, divert])

        await requester.finishEventStream(at: 0)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await requester.commands == [divert, divert])

        await requester.finishEventStream(at: 1)
        await Self.waitForCommandCount(3, requester: requester)
        #expect(await requester.commands == [divert, divert, restore])
    }

    @Test("a setup cancelled while waiting for ownership never diverts firmware")
    func cancelledWaitingSetupDoesNotDivert() async throws {
        let divert = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .divertButton
        )
        let restore = HIDPPCommands.setCIDReporting(
            featureIndex: 0x05,
            cid: 0x00C3,
            mode: .restoreButton
        )
        let requester = BlockingSetupHIDPPRequester()
        let controller = HIDPPDeviceController(
            requester: requester,
            identity: Self.identity(features: [.reprogrammableControlsV4: 0x05])
        )

        let firstSetup = Task {
            try await controller.specialInputEvents(
                for: [.gesture],
                rawXYButtons: [],
                timeout: .seconds(1)
            )
        }
        for _ in 0..<100 where !(await requester.firstRequestIsBlocked()) {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await requester.firstRequestIsBlocked())

        let cancelledSetup = Task {
            try await controller.specialInputEvents(
                for: [.gesture],
                rawXYButtons: [],
                timeout: .seconds(1)
            )
        }
        try? await Task.sleep(for: .milliseconds(10))
        cancelledSetup.cancel()
        await requester.releaseFirstRequest()

        let firstStream = try await firstSetup.value
        do {
            _ = try await cancelledSetup.value
            Issue.record("cancelled setup unexpectedly returned a stream")
        } catch is CancellationError {
            // Expected: cancellation is rechecked after the ownership wait.
        } catch {
            Issue.record("cancelled setup failed with unexpected error: \(error)")
        }
        #expect(await requester.commands == [divert])

        await requester.finishEventStream(at: 0)
        for try await _ in firstStream {}
        await Self.waitForCommandCount(2, requester: requester)
        #expect(await requester.commands == [divert, restore])
    }

    private static func identity(features: [HIDPPFeature: UInt8]) -> HIDPPDeviceIdentity {
        HIDPPDeviceIdentity(deviceIndex: 0x01, name: "MX Master 3", featureIndexes: features)
    }

    private static func response(_ featureIndex: UInt8, _ parameters: [UInt8]) -> HIDPPResponse {
        HIDPPResponse(
            deviceIndex: 0x01,
            featureIndex: featureIndex,
            function: 0x01,
            softwareID: HIDPPCodec.softwareID,
            parameters: parameters
        )
    }


    private static func event(
        _ featureIndex: UInt8,
        _ parameters: [UInt8],
        function: UInt8 = 0
    ) -> HIDPPResponse {
        HIDPPResponse(
            deviceIndex: 0x01,
            featureIndex: featureIndex,
            function: function,
            softwareID: 0,
            parameters: parameters
        )
    }

    private static func waitForCommandCount(
        _ expectedCount: Int,
        requester: RestartableHIDPPRequester
    ) async {
        for _ in 0..<100 {
            if await requester.commands.count >= expectedCount { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private static func waitForCommandCount(
        _ expectedCount: Int,
        requester: BlockingSetupHIDPPRequester
    ) async {
        for _ in 0..<100 {
            if await requester.commands.count >= expectedCount { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
