import Testing
@testable import MouserNative

@Suite("HID++ protocol")
struct HIDPPProtocolTests {
    @Test("long requests use the HID++ software identifier and pad to 20 bytes")
    func encodesLongRequest() throws {
        let bytes = try HIDPPCodec.encodeRequest(
            deviceIndex: 0x01,
            featureIndex: 0x05,
            function: 0x03,
            parameters: [0x00, 0x06, 0x40]
        )

        #expect(bytes.count == 20)
        #expect(Array(bytes.prefix(7)) == [0x11, 0x01, 0x05, 0x3A, 0x00, 0x06, 0x40])
        #expect(bytes.dropFirst(7).allSatisfy { $0 == 0 })
    }

    @Test("responses decode with or without the report identifier")
    func decodesResponseLayouts() throws {
        let full = try HIDPPCodec.decodeResponse([0x11, 0x01, 0x05, 0x4A, 0x00, 0x06, 0x40])
        let stripped = try HIDPPCodec.decodeResponse([0x01, 0x05, 0x4A, 0x00, 0x06, 0x40])

        #expect(full.deviceIndex == 0x01)
        #expect(full.featureIndex == 0x05)
        #expect(full.function == 0x04)
        #expect(full.softwareID == 0x0A)
        #expect(full.parameters == [0x00, 0x06, 0x40])
        #expect(stripped == full)
        #expect(HIDPPCodec.matches(full, featureIndex: 0x05, function: 0x03))
    }

    @Test("HID++ errors expose their protocol error code")
    func decodesErrorResponse() throws {
        let response = try HIDPPCodec.decodeResponse([0x11, 0x01, 0xFF, 0x0A, 0x05, 0x07])

        #expect(response.isError)
        #expect(response.errorCode == 0x07)
    }

    @Test("feature discovery uses IRoot and the big-endian feature identifier")
    func buildsFeatureDiscovery() {
        let command = HIDPPCommands.discover(.adjustableDPI)

        #expect(command.featureIndex == 0x00)
        #expect(command.function == 0x00)
        #expect(command.parameters == [0x22, 0x01, 0x00])
    }

    @Test("DPI commands use sensor zero and a big-endian DPI value")
    func buildsDPICommands() {
        #expect(
            HIDPPCommands.setDPI(featureIndex: 0x08, dpi: 1600) ==
                HIDPPCommand(featureIndex: 0x08, function: 0x03, parameters: [0x00, 0x06, 0x40])
        )
        #expect(
            HIDPPCommands.readDPI(featureIndex: 0x08) ==
                HIDPPCommand(featureIndex: 0x08, function: 0x02, parameters: [0x00])
        )
    }

    @Test("enhanced SmartShift clamps sensitivity and scroll force")
    func buildsEnhancedSmartShiftCommands() {
        let automatic = HIDPPCommands.setSmartShift(
            featureIndex: 0x09,
            enhanced: true,
            mode: .ratchet,
            automatic: true,
            threshold: 80,
            scrollForce: 0
        )
        let fixedFreeSpin = HIDPPCommands.setSmartShift(
            featureIndex: 0x09,
            enhanced: true,
            mode: .freeSpin,
            automatic: false,
            threshold: 25,
            scrollForce: 72
        )

        #expect(automatic.function == 0x02)
        #expect(automatic.parameters == [0x02, 50, 1])
        #expect(fixedFreeSpin.parameters == [0x01, 0x00, 72])
        #expect(HIDPPCommands.readSmartShift(featureIndex: 0x09, enhanced: true).function == 0x01)
    }

    @Test("basic SmartShift omits scroll force and fixed ratchet disables auto switching")
    func buildsBasicSmartShiftCommands() {
        let fixedRatchet = HIDPPCommands.setSmartShift(
            featureIndex: 0x09,
            enhanced: false,
            mode: .ratchet,
            automatic: false,
            threshold: 25,
            scrollForce: 90
        )

        #expect(fixedRatchet.function == 0x01)
        #expect(fixedRatchet.parameters == [0x02, 0xFF, 0x00])
        #expect(HIDPPCommands.readSmartShift(featureIndex: 0x09, enhanced: false).function == 0x00)
    }

    @Test("haptic levels and battery reads match Mouser's HID++ payloads")
    func buildsHapticAndBatteryCommands() {
        #expect(
            HIDPPCommands.setHapticLevel(featureIndex: 0x0B, level: 2) ==
                HIDPPCommand(featureIndex: 0x0B, function: 0x02, parameters: [0x01, 75])
        )
        #expect(HIDPPCommands.readBattery(featureIndex: 0x0C, unified: true).function == 0x01)
        #expect(HIDPPCommands.readBattery(featureIndex: 0x0C, unified: false).function == 0x00)
        #expect(HIDPPCommands.parseBattery(parameters: [82, 0, 1]) == .init(level: 82, charging: true))
        #expect(HIDPPCommands.parseBattery(parameters: [101, 0, 0]) == nil)
    }

    @Test("device state parsers decode DPI and SmartShift without guessing missing bytes")
    func parsesDeviceSettings() {
        #expect(HIDPPCommands.parseDPI(parameters: [0x00, 0x06, 0x40]) == 1600)
        #expect(HIDPPCommands.parseDPI(parameters: [0x00, 0x06]) == nil)
        #expect(
            HIDPPCommands.parseSmartShift(parameters: [0x02, 25, 60]) ==
                HIDPPSmartShiftState(mode: .ratchet, automatic: true, threshold: 25, scrollForce: 60)
        )
        #expect(
            HIDPPCommands.parseSmartShift(parameters: [0x01, 25]) ==
                HIDPPSmartShiftState(mode: .freeSpin, automatic: false, threshold: 25, scrollForce: 0)
        )
        #expect(
            HIDPPCommands.parseSmartShift(parameters: [0x02, 0xFF]) ==
                HIDPPSmartShiftState(mode: .ratchet, automatic: false, threshold: 25, scrollForce: 0)
        )
        #expect(HIDPPCommands.parseSmartShift(parameters: []) == nil)
    }

    @Test("wheel inversion commands preserve the firmware mode outside the invert bit")
    func buildsWheelInversionCommands() {
        #expect(
            HIDPPCommands.readWheelMode(featureIndex: 0x0E) ==
                HIDPPCommand(featureIndex: 0x0E, function: 0x01, parameters: [])
        )
        #expect(
            HIDPPCommands.setWheelMode(featureIndex: 0x0E, mode: 0x06) ==
                HIDPPCommand(featureIndex: 0x0E, function: 0x02, parameters: [0x06])
        )
        #expect(HIDPPCommands.wheelMode(0x03, verticallyInverted: true) == 0x06)
        #expect(HIDPPCommands.wheelMode(0x06, verticallyInverted: false) == 0x02)
        #expect(
            HIDPPCommands.setThumbWheelInverted(featureIndex: 0x0F, inverted: true) ==
                HIDPPCommand(featureIndex: 0x0F, function: 0x02, parameters: [0x00, 0x01])
        )
    }

    @Test("scroll modes expose concise localized hardware labels")
    func scrollModeLabels() {
        #expect(SmartShiftMode.ratchet.title == "棘轮")
        #expect(SmartShiftMode.freeSpin.title == "飞轮")
    }
}
