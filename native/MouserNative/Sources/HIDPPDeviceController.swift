import Foundation

struct HIDPPDeviceState: Equatable, Sendable {
    let dpi: Int?
    let smartShift: HIDPPSmartShiftState?
    let battery: HIDPPBatteryState?
    let verticalScrollInverted: Bool?
    var forceSensing: HIDPPForceSensingState? = nil
}

struct HIDPPForceSensingState: Equatable, Sendable {
    let minimum: Int
    let maximum: Int
    let defaultValue: Int
    let currentValue: Int
    let isChangeable: Bool
}

struct HIDPPReprogrammableControl: Equatable, Sendable {
    let index: Int
    let cid: UInt16
    let taskID: UInt16
    let flags: UInt16
    let mappingFlags: UInt16

    var isDivertable: Bool { flags & 0x0020 != 0 }

    var supportsRawXY: Bool {
        flags & (0x0100 | 0x0200) != 0 ||
            mappingFlags & (0x0010 | 0x0040) != 0
    }
}

enum HIDPPDeviceControlError: Error, Equatable {
    case unsupportedFeature(HIDPPFeature)
    case invalidResponse(HIDPPFeature)
    case dpiOutOfRange(Int)
    case eventStreamUnavailable
}

protocol HIDPPDeviceControlling: Sendable {
    func readState(timeout: Duration) async -> HIDPPDeviceState
    func readBatteryState(timeout: Duration) async -> HIDPPBatteryState?
    func setDPI(_ dpi: Int, timeout: Duration) async throws
    func setSmartShift(
        mode: SmartShiftMode,
        automatic: Bool,
        threshold: Int,
        scrollForce: Int,
        timeout: Duration
    ) async throws
    func setVerticalScrollInverted(_ inverted: Bool, timeout: Duration) async throws
    func setHorizontalScrollInverted(_ inverted: Bool, timeout: Duration) async throws
    func setHapticLevel(_ level: Int, timeout: Duration) async throws
    func playHapticWaveform(_ waveformID: Int, timeout: Duration) async throws
    func setForceSensing(_ value: Int, timeout: Duration) async throws
    func readReprogrammableControls(
        timeout: Duration
    ) async -> [HIDPPReprogrammableControl]
    func specialButtonEvents(
        for buttons: Set<MouseButton>,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<HIDPPButtonEvent, any Error>
    func specialInputEvents(
        for buttons: Set<MouseButton>,
        rawXYButtons: Set<MouseButton>,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<HIDPPSpecialInputEvent, any Error>
}

extension HIDPPDeviceControlling {
    func readBatteryState(timeout: Duration) async -> HIDPPBatteryState? {
        await readState(timeout: timeout).battery
    }

    func readReprogrammableControls(
        timeout: Duration
    ) async -> [HIDPPReprogrammableControl] {
        _ = timeout
        return []
    }

    func specialButtonEvents(
        for buttons: Set<MouseButton>,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<HIDPPButtonEvent, any Error> {
        _ = buttons
        _ = timeout
        return AsyncThrowingStream { $0.finish() }
    }

    func specialInputEvents(
        for buttons: Set<MouseButton>,
        rawXYButtons: Set<MouseButton>,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<HIDPPSpecialInputEvent, any Error> {
        _ = buttons
        _ = rawXYButtons
        _ = timeout
        return AsyncThrowingStream { $0.finish() }
    }
}

struct HIDPPDeviceController: HIDPPDeviceControlling, Sendable {
    private let requester: any HIDPPRequesting
    let identity: HIDPPDeviceIdentity

    init(requester: any HIDPPRequesting, identity: HIDPPDeviceIdentity) {
        self.requester = requester
        self.identity = identity
    }

    func readState(timeout: Duration = .seconds(2)) async -> HIDPPDeviceState {
        HIDPPDeviceState(
            dpi: await readDPI(timeout: timeout),
            smartShift: await readSmartShift(timeout: timeout),
            battery: await readBattery(timeout: timeout),
            verticalScrollInverted: await readVerticalScrollInversion(timeout: timeout),
            forceSensing: await readForceSensing(timeout: timeout)
        )
    }

    func readBatteryState(timeout: Duration = .seconds(2)) async -> HIDPPBatteryState? {
        await readBattery(timeout: timeout)
    }

    func setDPI(_ dpi: Int, timeout: Duration = .seconds(2)) async throws {
        guard let value = UInt16(exactly: dpi) else {
            throw HIDPPDeviceControlError.dpiOutOfRange(dpi)
        }
        let featureIndex = try requiredIndex(for: .adjustableDPI)
        _ = try await requester.request(
            HIDPPCommands.setDPI(featureIndex: featureIndex, dpi: value),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func setSmartShift(
        mode: SmartShiftMode,
        automatic: Bool,
        threshold: Int,
        scrollForce: Int,
        timeout: Duration = .seconds(2)
    ) async throws {
        let feature = smartShiftFeature
        let featureIndex = try requiredIndex(for: feature)
        _ = try await requester.request(
            HIDPPCommands.setSmartShift(
                featureIndex: featureIndex,
                enhanced: feature == .smartShiftEnhanced,
                mode: mode,
                automatic: automatic,
                threshold: threshold,
                scrollForce: scrollForce
            ),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func setVerticalScrollInverted(
        _ inverted: Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        let featureIndex = try requiredIndex(for: .highResolutionWheelEnhanced)
        let current = try await requester.request(
            HIDPPCommands.readWheelMode(featureIndex: featureIndex),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
        guard let currentMode = current.parameters.first else {
            throw HIDPPDeviceControlError.invalidResponse(.highResolutionWheelEnhanced)
        }
        let targetMode = HIDPPCommands.wheelMode(
            currentMode,
            verticallyInverted: inverted
        )
        guard targetMode != currentMode else { return }
        _ = try await requester.request(
            HIDPPCommands.setWheelMode(featureIndex: featureIndex, mode: targetMode),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func setHorizontalScrollInverted(
        _ inverted: Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        let featureIndex = try requiredIndex(for: .thumbWheel)
        _ = try await requester.request(
            HIDPPCommands.setThumbWheelInverted(
                featureIndex: featureIndex,
                inverted: inverted
            ),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func setHapticLevel(_ level: Int, timeout: Duration = .seconds(2)) async throws {
        let featureIndex = try requiredIndex(for: .haptic)
        _ = try await requester.request(
            HIDPPCommands.setHapticLevel(featureIndex: featureIndex, level: level),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func playHapticWaveform(
        _ waveformID: Int,
        timeout: Duration = .seconds(2)
    ) async throws {
        let featureIndex = try requiredIndex(for: .haptic)
        _ = try await requester.request(
            HIDPPCommands.playHapticWaveform(
                featureIndex: featureIndex,
                waveformID: waveformID
            ),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func setForceSensing(_ value: Int, timeout: Duration = .seconds(2)) async throws {
        let featureIndex = try requiredIndex(for: .forceSensing)
        _ = try await requester.request(
            HIDPPCommands.setForceSensing(featureIndex: featureIndex, value: value),
            deviceIndex: identity.deviceIndex,
            timeout: timeout
        )
    }

    func readReprogrammableControls(
        timeout: Duration = .seconds(2)
    ) async -> [HIDPPReprogrammableControl] {
        guard let featureIndex = identity.featureIndexes[.reprogrammableControlsV4],
              let countResponse = try? await requester.request(
                HIDPPCommands.readReprogrammableControlCount(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
              )
        else { return [] }

        let count = min(32, Int(countResponse.parameters.first ?? 0))
        var controls: [HIDPPReprogrammableControl] = []
        var consecutiveFailures = 0
        for index in 0..<count {
            guard let response = try? await requester.request(
                HIDPPCommands.readReprogrammableControl(
                    featureIndex: featureIndex,
                    index: UInt8(index)
                ),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            ), response.parameters.count >= 9
            else {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 { break }
                continue
            }
            consecutiveFailures = 0
            let parameters = response.parameters
            let cid = UInt16(parameters[0]) << 8 | UInt16(parameters[1])
            let taskID = UInt16(parameters[2]) << 8 | UInt16(parameters[3])
            let flags = UInt16(parameters[4]) | UInt16(parameters[8]) << 8
            var mappingFlags = UInt16(0)
            if let reporting = try? await requester.request(
                HIDPPCommands.readCIDReporting(featureIndex: featureIndex, cid: cid),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            ), reporting.parameters.count >= 3 {
                mappingFlags = UInt16(reporting.parameters[2])
                if reporting.parameters.count >= 6 {
                    mappingFlags |= UInt16(reporting.parameters[5]) << 8
                }
            }
            controls.append(HIDPPReprogrammableControl(
                index: index,
                cid: cid,
                taskID: taskID,
                flags: flags,
                mappingFlags: mappingFlags
            ))
        }
        return controls
    }

    private func readForceSensing(timeout: Duration) async -> HIDPPForceSensingState? {
        guard let featureIndex = identity.featureIndexes[.forceSensing] else { return nil }
        do {
            let count = try await requester.request(
                HIDPPCommands.readForceSensingCount(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            )
            guard (count.parameters.first ?? 0) >= 1 else { return nil }
            let configuration = try await requester.request(
                HIDPPCommands.readForceSensingConfiguration(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            )
            let current = try await requester.request(
                HIDPPCommands.readForceSensingCurrent(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            )
            guard configuration.parameters.count >= 8, current.parameters.count >= 2 else {
                return nil
            }
            func uint16(_ bytes: [UInt8], at offset: Int) -> Int {
                Int(UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]))
            }
            return HIDPPForceSensingState(
                minimum: uint16(configuration.parameters, at: 6),
                maximum: uint16(configuration.parameters, at: 4),
                defaultValue: uint16(configuration.parameters, at: 2),
                currentValue: uint16(current.parameters, at: 0),
                isChangeable: uint16(configuration.parameters, at: 0) & 0x01 != 0
            )
        } catch {
            return nil
        }
    }

    func specialButtonEvents(
        for buttons: Set<MouseButton>,
        timeout: Duration = .seconds(2)
    ) async throws -> AsyncThrowingStream<HIDPPButtonEvent, any Error> {
        let inputs = try await specialInputEvents(
            for: buttons,
            rawXYButtons: [],
            timeout: timeout
        )
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: HIDPPButtonEvent.self,
            throwing: (any Error).self
        )
        let task = Task.detached {
            do {
                for try await input in inputs {
                    guard !Task.isCancelled else { break }
                    if case let .button(event) = input {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func specialInputEvents(
        for buttons: Set<MouseButton>,
        rawXYButtons: Set<MouseButton>,
        timeout: Duration = .seconds(2)
    ) async throws -> AsyncThrowingStream<HIDPPSpecialInputEvent, any Error> {
        let featureIndex = try requiredIndex(for: .reprogrammableControlsV4)
        guard let eventStreamer = requester as? any HIDPPEventStreaming else {
            throw HIDPPDeviceControlError.eventStreamUnavailable
        }
        let buttonsByCID = Self.specialButtonsByCID.filter { buttons.contains($0.value) }
        guard !buttonsByCID.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        var restoreModes: [UInt16: HIDPPCIDReportingMode] = [:]
        do {
            for cid in buttonsByCID.keys.sorted() {
                let button = buttonsByCID[cid]
                let rawXY = button.map(rawXYButtons.contains) ?? false
                _ = try await requester.request(
                    HIDPPCommands.setCIDReporting(
                        featureIndex: featureIndex,
                        cid: cid,
                        mode: rawXY ? .divertRawXY : .divertButton
                    ),
                    deviceIndex: identity.deviceIndex,
                    timeout: timeout
                )
                restoreModes[cid] = rawXY ? .restoreRawXY : .restoreButton
            }
        } catch {
            await restoreCIDs(restoreModes, featureIndex: featureIndex, timeout: timeout)
            throw error
        }

        let responses: AsyncThrowingStream<HIDPPResponse, any Error>
        do {
            responses = try await eventStreamer.events()
        } catch {
            await restoreCIDs(restoreModes, featureIndex: featureIndex, timeout: timeout)
            throw error
        }

        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: HIDPPSpecialInputEvent.self,
            throwing: (any Error).self
        )
        let controller = self
        let task = Task.detached {
            var router = HIDPPSpecialInputRouter(
                featureIndex: featureIndex,
                buttonsByCID: buttonsByCID
            )
            do {
                for try await response in responses {
                    guard !Task.isCancelled else { break }
                    for event in router.route(response) {
                        continuation.yield(event)
                    }
                }
                await controller.restoreCIDs(
                    restoreModes,
                    featureIndex: featureIndex,
                    timeout: timeout
                )
                continuation.finish()
            } catch {
                await controller.restoreCIDs(
                    restoreModes,
                    featureIndex: featureIndex,
                    timeout: timeout
                )
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func restoreCIDs(
        _ modes: [UInt16: HIDPPCIDReportingMode],
        featureIndex: UInt8,
        timeout: Duration
    ) async {
        for cid in modes.keys.sorted() {
            guard let mode = modes[cid] else { continue }
            _ = try? await requester.request(
                HIDPPCommands.setCIDReporting(
                    featureIndex: featureIndex,
                    cid: cid,
                    mode: mode
                ),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
            )
        }
    }

    private static let specialButtonsByCID: [UInt16: MouseButton] = [
        0x00C3: .gesture,
        0x00C4: .modeShift,
        0x01A0: .actionsRing,
        0x00FD: .dpiSwitch,
    ]

    private var smartShiftFeature: HIDPPFeature {
        identity.featureIndexes[.smartShiftEnhanced] != nil
            ? .smartShiftEnhanced
            : .smartShift
    }

    private func requiredIndex(for feature: HIDPPFeature) throws -> UInt8 {
        guard let index = identity.featureIndexes[feature] else {
            throw HIDPPDeviceControlError.unsupportedFeature(feature)
        }
        return index
    }

    private func readDPI(timeout: Duration) async -> Int? {
        guard let featureIndex = identity.featureIndexes[.adjustableDPI],
              let response = try? await requester.request(
                HIDPPCommands.readDPI(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
              )
        else { return nil }
        return HIDPPCommands.parseDPI(parameters: response.parameters)
    }

    private func readSmartShift(timeout: Duration) async -> HIDPPSmartShiftState? {
        let feature = smartShiftFeature
        guard let featureIndex = identity.featureIndexes[feature],
              let response = try? await requester.request(
                HIDPPCommands.readSmartShift(
                    featureIndex: featureIndex,
                    enhanced: feature == .smartShiftEnhanced
                ),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
              )
        else { return nil }
        return HIDPPCommands.parseSmartShift(parameters: response.parameters)
    }

    private func readBattery(timeout: Duration) async -> HIDPPBatteryState? {
        let feature: HIDPPFeature = identity.featureIndexes[.unifiedBattery] != nil
            ? .unifiedBattery
            : .batteryStatus
        guard let featureIndex = identity.featureIndexes[feature],
              let response = try? await requester.request(
                HIDPPCommands.readBattery(
                    featureIndex: featureIndex,
                    unified: feature == .unifiedBattery
                ),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
              )
        else { return nil }
        return HIDPPCommands.parseBattery(parameters: response.parameters)
    }

    private func readVerticalScrollInversion(timeout: Duration) async -> Bool? {
        guard let featureIndex = identity.featureIndexes[.highResolutionWheelEnhanced],
              let response = try? await requester.request(
                HIDPPCommands.readWheelMode(featureIndex: featureIndex),
                deviceIndex: identity.deviceIndex,
                timeout: timeout
              ),
              let mode = response.parameters.first
        else { return nil }
        return mode & 0x04 != 0
    }
}
