import Testing
@testable import MouserNative

@Suite("HID++ diverted button routing")
struct HIDPPButtonEventRouterTests {
    @Test("CID reports become ordered down and up transitions")
    func routesButtonTransitions() {
        var router = HIDPPButtonEventRouter(
            featureIndex: 0x05,
            buttonsByCID: [
                0x00C3: .gesture,
                0x00C4: .modeShift,
                0x01A0: .actionsRing,
                0x00FD: .dpiSwitch,
            ]
        )

        #expect(router.route(Self.report([0x00, 0xC3, 0x00, 0xC4, 0x00, 0x00])) == [
            .init(button: .gesture, isPressed: true),
            .init(button: .modeShift, isPressed: true),
        ])
        #expect(router.route(Self.report([0x00, 0xC4, 0x00, 0x00])) == [
            .init(button: .gesture, isPressed: false),
        ])
        #expect(router.route(Self.report([0x00, 0x00])) == [
            .init(button: .modeShift, isPressed: false),
        ])

        #expect(router.route(Self.report([0x01, 0xA0, 0x00, 0x00])) == [
            .init(button: .actionsRing, isPressed: true),
        ])
        #expect(router.route(Self.report([0x00, 0x00])) == [
            .init(button: .actionsRing, isPressed: false),
        ])
        #expect(router.route(Self.report([0x00, 0xFD, 0x00, 0x00])) == [
            .init(button: .dpiSwitch, isPressed: true),
        ])
        #expect(router.route(Self.report([0x00, 0x00])) == [
            .init(button: .dpiSwitch, isPressed: false),
        ])
    }

    @Test("unrelated feature and raw movement reports are ignored")
    func ignoresUnrelatedReports() {
        var router = HIDPPButtonEventRouter(
            featureIndex: 0x05,
            buttonsByCID: [0x00C3: .gesture]
        )

        #expect(router.route(Self.report([0x00, 0xC3], featureIndex: 0x08)).isEmpty)
        #expect(router.route(Self.report([0x00, 0xC3], function: 1)).isEmpty)
    }

    @Test("raw XY reports decode signed movement alongside button transitions")
    func routesRawMovement() {
        var router = HIDPPSpecialInputRouter(
            featureIndex: 0x05,
            buttonsByCID: [0x00C3: .gesture]
        )

        #expect(router.route(Self.report([0xFF, 0xF6, 0x00, 0x14], function: 1)) == [
            .movement(dx: -10, dy: 20),
        ])
        #expect(router.route(Self.report([0x00, 0xC3, 0x00, 0x00])) == [
            .button(.init(button: .gesture, isPressed: true)),
        ])
    }

    @Test("divert and restore commands preserve the persistent firmware bit")
    func reportingCommands() {
        #expect(
            HIDPPCommands.setCIDReporting(
                featureIndex: 0x05,
                cid: 0x00C4,
                mode: .divertButton
            ) == HIDPPCommand(
                featureIndex: 0x05,
                function: 0x03,
                parameters: [0x00, 0xC4, 0x03, 0x00, 0x00]
            )
        )
        #expect(
            HIDPPCommands.setCIDReporting(
                featureIndex: 0x05,
                cid: 0x00C4,
                mode: .restoreButton
            ).parameters == [0x00, 0xC4, 0x02, 0x00, 0x00]
        )
    }

    private static func report(
        _ parameters: [UInt8],
        featureIndex: UInt8 = 0x05,
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
}
