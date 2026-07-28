import Foundation

enum HIDPPFeature: UInt16, CaseIterable, Hashable, Sendable {
    case root = 0x0000
    case deviceName = 0x0005
    case unifiedBattery = 0x1004
    case batteryStatus = 0x1000
    case haptic = 0x19B0
    case forceSensing = 0x19C0
    case smartShift = 0x2110
    case smartShiftEnhanced = 0x2111
    case highResolutionWheel = 0x2120
    case highResolutionWheelEnhanced = 0x2121
    case lowResolutionWheel = 0x2130
    case thumbWheel = 0x2150
    case adjustableDPI = 0x2201
    case reprogrammableControlsV4 = 0x1B04
}

struct HIDPPCommand: Equatable, Hashable, Sendable {
    let featureIndex: UInt8
    let function: UInt8
    let parameters: [UInt8]
}

struct HIDPPResponse: Equatable, Sendable {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let function: UInt8
    let softwareID: UInt8
    let parameters: [UInt8]

    var isError: Bool { featureIndex == 0xFF }

    var errorCode: UInt8? {
        guard isError, parameters.count > 1 else { return nil }
        return parameters[1]
    }
}

enum HIDPPCIDReportingMode: UInt8, Sendable {
    case divertButton = 0x03
    case divertRawXY = 0x33
    case restoreButton = 0x02
    case restoreRawXY = 0x22
}

enum HIDPPCodecError: Error, Equatable {
    case invalidFunction(UInt8)
    case tooManyParameters(Int)
    case responseTooShort(Int)
}

enum HIDPPCodec {
    static let longReportID: UInt8 = 0x11
    static let shortReportID: UInt8 = 0x10
    static let longReportLength = 20
    static let softwareID: UInt8 = 0x0A

    static func encodeRequest(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        softwareID: UInt8 = softwareID
    ) throws -> [UInt8] {
        guard function <= 0x0F else { throw HIDPPCodecError.invalidFunction(function) }
        precondition(softwareID <= 0x0F, "HID++ software ID must fit in four bits")
        let capacity = longReportLength - 4
        guard parameters.count <= capacity else {
            throw HIDPPCodecError.tooManyParameters(parameters.count)
        }

        var report = [UInt8](repeating: 0, count: longReportLength)
        report[0] = longReportID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (function << 4) | softwareID
        report.replaceSubrange(4..<(4 + parameters.count), with: parameters)
        return report
    }

    static func decodeResponse(_ bytes: [UInt8]) throws -> HIDPPResponse {
        let hasReportID = bytes.first == longReportID || bytes.first == shortReportID
        let offset = hasReportID ? 1 : 0
        guard bytes.count >= offset + 3 else {
            throw HIDPPCodecError.responseTooShort(bytes.count)
        }
        let functionAndSoftware = bytes[offset + 2]
        return HIDPPResponse(
            deviceIndex: bytes[offset],
            featureIndex: bytes[offset + 1],
            function: functionAndSoftware >> 4,
            softwareID: functionAndSoftware & 0x0F,
            parameters: Array(bytes.dropFirst(offset + 3))
        )
    }

    static func matches(
        _ response: HIDPPResponse,
        featureIndex: UInt8,
        function: UInt8,
        softwareID: UInt8 = softwareID
    ) -> Bool {
        guard !response.isError,
              response.featureIndex == featureIndex,
              response.softwareID == softwareID
        else { return false }
        return response.function == function || response.function == ((function + 1) & 0x0F)
    }
}

enum SmartShiftMode: String, CaseIterable, Equatable, Identifiable, Sendable {
    case ratchet
    case freeSpin = "freespin"

    var id: Self { self }

    var title: String {
        switch self {
        case .ratchet: "棘轮"
        case .freeSpin: "飞轮"
        }
    }

    var protocolValue: UInt8 {
        switch self {
        case .ratchet: 0x02
        case .freeSpin: 0x01
        }
    }
}

struct HIDPPBatteryState: Equatable, Sendable {
    let level: Int
    let charging: Bool
}

struct HIDPPSmartShiftState: Equatable, Sendable {
    let mode: SmartShiftMode
    let automatic: Bool
    let threshold: Int
    let scrollForce: Int
}

enum HIDPPCommands {
    static func readReprogrammableControlCount(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x00, parameters: [])
    }

    static func readReprogrammableControl(
        featureIndex: UInt8,
        index: UInt8
    ) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x01, parameters: [index])
    }

    static func readCIDReporting(featureIndex: UInt8, cid: UInt16) -> HIDPPCommand {
        HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x02,
            parameters: [UInt8(cid >> 8), UInt8(cid & 0x00FF)]
        )
    }

    static func setCIDReporting(
        featureIndex: UInt8,
        cid: UInt16,
        mode: HIDPPCIDReportingMode
    ) -> HIDPPCommand {
        HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x03,
            parameters: [
                UInt8(cid >> 8),
                UInt8(cid & 0x00FF),
                mode.rawValue,
                0x00,
                0x00,
            ]
        )
    }

    static func discover(_ feature: HIDPPFeature) -> HIDPPCommand {
        let value = feature.rawValue
        return HIDPPCommand(
            featureIndex: 0x00,
            function: 0x00,
            parameters: [UInt8(value >> 8), UInt8(value & 0xFF), 0x00]
        )
    }

    static func setDPI(featureIndex: UInt8, dpi: UInt16) -> HIDPPCommand {
        HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x03,
            parameters: [0x00, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]
        )
    }

    static func readDPI(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x02, parameters: [0x00])
    }

    static func parseDPI(parameters: [UInt8]) -> Int? {
        guard parameters.count >= 3 else { return nil }
        return Int(parameters[1]) << 8 | Int(parameters[2])
    }

    static func setSmartShift(
        featureIndex: UInt8,
        enhanced: Bool,
        mode: SmartShiftMode,
        automatic: Bool,
        threshold: Int,
        scrollForce: Int
    ) -> HIDPPCommand {
        let force = enhanced ? UInt8(scrollForce.clamped(to: 1...100)) : 0x00
        let autoDisengage: UInt8
        if automatic {
            autoDisengage = UInt8(threshold.clamped(to: 1...50))
        } else if mode == .freeSpin {
            autoDisengage = 0x00
        } else {
            autoDisengage = 0xFF
        }
        return HIDPPCommand(
            featureIndex: featureIndex,
            function: enhanced ? 0x02 : 0x01,
            parameters: [automatic ? SmartShiftMode.ratchet.protocolValue : mode.protocolValue, autoDisengage, force]
        )
    }

    static func readSmartShift(featureIndex: UInt8, enhanced: Bool) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: enhanced ? 0x01 : 0x00, parameters: [])
    }

    static func parseSmartShift(parameters: [UInt8]) -> HIDPPSmartShiftState? {
        guard let modeByte = parameters.first else { return nil }
        let autoDisengage = parameters.count > 1 ? Int(parameters[1]) : 0
        let scrollForce = parameters.count > 2 ? Int(parameters[2]) : 0
        let mode: SmartShiftMode = modeByte == SmartShiftMode.freeSpin.protocolValue
            ? .freeSpin
            : .ratchet
        let automatic = mode == .ratchet && (1...50).contains(autoDisengage)
        return HIDPPSmartShiftState(
            mode: mode,
            automatic: automatic,
            threshold: (1...50).contains(autoDisengage) ? autoDisengage : 25,
            scrollForce: scrollForce
        )
    }

    static func readWheelMode(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x01, parameters: [])
    }

    static func setWheelMode(featureIndex: UInt8, mode: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x02, parameters: [mode])
    }

    static func wheelMode(_ currentMode: UInt8, verticallyInverted: Bool) -> UInt8 {
        let targetBit: UInt8 = 0x01
        let invertBit: UInt8 = 0x04
        return (currentMode & ~(targetBit | invertBit)) |
            (verticallyInverted ? invertBit : 0)
    }

    static func setThumbWheelInverted(
        featureIndex: UInt8,
        inverted: Bool
    ) -> HIDPPCommand {
        HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x02,
            parameters: [0x00, inverted ? 0x01 : 0x00]
        )
    }

    static func setHapticLevel(featureIndex: UInt8, level: Int) -> HIDPPCommand {
        let deviceLevels: [UInt8] = [25, 50, 75, 100]
        return HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x02,
            parameters: [0x01, deviceLevels[level.clamped(to: 0...3)]]
        )
    }

    static func playHapticWaveform(featureIndex: UInt8, waveformID: Int) -> HIDPPCommand {
        HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x04,
            parameters: [UInt8(clamping: waveformID)]
        )
    }

    static func setForceSensing(featureIndex: UInt8, value: Int) -> HIDPPCommand {
        let clamped = UInt16(clamping: value)
        return HIDPPCommand(
            featureIndex: featureIndex,
            function: 0x03,
            parameters: [0x00, UInt8(clamped >> 8), UInt8(clamped & 0x00FF)]
        )
    }

    static func readForceSensingCount(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x00, parameters: [])
    }

    static func readForceSensingConfiguration(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x01, parameters: [0x00])
    }

    static func readForceSensingCurrent(featureIndex: UInt8) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: 0x02, parameters: [0x00])
    }

    static func readBattery(featureIndex: UInt8, unified: Bool) -> HIDPPCommand {
        HIDPPCommand(featureIndex: featureIndex, function: unified ? 0x01 : 0x00, parameters: [])
    }

    static func parseBattery(parameters: [UInt8]) -> HIDPPBatteryState? {
        guard let level = parameters.first, level <= 100 else { return nil }
        let chargeState = parameters.count > 2 ? parameters[2] : 0
        return HIDPPBatteryState(
            level: Int(level),
            charging: (1...4).contains(chargeState)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
