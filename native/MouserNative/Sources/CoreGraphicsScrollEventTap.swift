import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

enum ScrollEventTapState: Equatable, Sendable {
    case stopped
    case waitingForPermission
    case running
    case failed(String)
}

protocol ScrollEventTapping: AnyObject {
    var state: ScrollEventTapState { get }
    func updateSettings(_ settings: ScrollInversionSettings)
    func updateHorizontalScrollThreshold(_ threshold: Double)
    func updateGestureSettings(_ settings: GestureRecognitionSettings)
    func updateButtonMappings(
        _ mappings: [MouseButton: String],
        gestureMappings: [String: String],
        actionHandler: @escaping @Sendable (MappedActionInvocation) -> Void
    )
    func beginExternalGesture(for button: MouseButton)
    func endExternalGesture(for button: MouseButton)
    @discardableResult func start() -> Bool
    func stop()
    @discardableResult func rebuild() -> Bool
}

extension ScrollEventTapping {
    func updateGestureSettings(_ settings: GestureRecognitionSettings) {
        _ = settings
    }

    func updateHorizontalScrollThreshold(_ threshold: Double) {
        _ = threshold
    }

    func beginExternalGesture(for button: MouseButton) {
        _ = button
    }

    func endExternalGesture(for button: MouseButton) {
        _ = button
    }
}

private func mouserScrollEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let owner = Unmanaged<CoreGraphicsScrollEventTap>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return owner.handle(type: type, event: event)
}

final class CoreGraphicsScrollEventTap: ScrollEventTapping {
    private(set) var state: ScrollEventTapState = .stopped
    private var transformer = ScrollEventTransformer(
        settings: ScrollInversionSettings(
            invertVertical: false,
            invertHorizontal: false,
            ignoreTrackpad: true
        )
    )
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buttonRouter = MouseButtonEventRouter()
    private var gestureRecognizer = GestureRecognizer(threshold: 25)
    private var horizontalScrollRouter = HorizontalScrollActionRouter()
    private var activeGestureButton: MouseButton?
    private var gestureMappings: [String: String] = [:]
    private var buttonMappings: [MouseButton: String] = [:]
    private var buttonActionHandler: (@Sendable (MappedActionInvocation) -> Void)?

    func updateSettings(_ settings: ScrollInversionSettings) {
        transformer.settings = settings
    }

    func updateGestureSettings(_ settings: GestureRecognitionSettings) {
        gestureRecognizer = GestureRecognizer(
            threshold: settings.threshold,
            commitWindowMilliseconds: settings.commitWindowMilliseconds,
            settleMilliseconds: settings.settleMilliseconds,
            crossRatio: settings.crossRatio
        )
        activeGestureButton = nil
    }

    func updateHorizontalScrollThreshold(_ threshold: Double) {
        horizontalScrollRouter.threshold = max(0.01, threshold)
    }

    func updateButtonMappings(
        _ mappings: [MouseButton: String],
        gestureMappings: [String: String],
        actionHandler: @escaping @Sendable (MappedActionInvocation) -> Void
    ) {
        buttonRouter.updateMappings(mappings)
        buttonMappings = mappings
        self.gestureMappings = gestureMappings
        activeGestureButton = nil
        buttonActionHandler = actionHandler
    }

    func beginExternalGesture(for button: MouseButton) {
        activeGestureButton = button
        gestureRecognizer.begin()
    }

    func endExternalGesture(for button: MouseButton) {
        guard activeGestureButton == button else { return }
        let wasClick = gestureRecognizer.end()
        activeGestureButton = nil
        guard wasClick else { return }
        executeGestureMapping(for: button, slot: "tap")
    }

    @discardableResult
    func start() -> Bool {
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            state = .running
            return true
        }
        guard AXIsProcessTrusted() else {
            state = .waitingForPermission
            return false
        }

        stop()
        let eventMask = [
            CGEventType.scrollWheel,
            .otherMouseDown,
            .otherMouseUp,
            .mouseMoved,
            .otherMouseDragged,
        ].reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mouserScrollEventTapCallback,
            userInfo: userInfo
        ) else {
            state = .failed("无法创建 CGEventTap")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            state = .failed("无法创建事件 RunLoop source")
            return false
        }

        tap = newTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        guard CGEvent.tapIsEnabled(tap: newTap) else {
            stop()
            state = .failed("系统未启用 CGEventTap")
            return false
        }
        state = .running
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        state = .stopped
    }

    @discardableResult
    func rebuild() -> Bool {
        stop()
        return start()
    }

    func processScrollEvent(
        _ event: CGEvent,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        let sample = ScrollSample(
            vertical: axisDeltas(in: event, axis: 1),
            horizontal: axisDeltas(in: event, axis: 2),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
        var output = sample
        var shouldApply = false
        switch horizontalScrollRouter.route(
            sample,
            mappings: gestureMappings,
            uptime: uptime
        ) {
        case .passThrough:
            break
        case .consume:
            output.horizontal = .zero
            shouldApply = true
        case let .execute(actionID):
            output.horizontal = .zero
            shouldApply = true
            let buttonID = horizontalButtonID(for: sample.horizontal)
            buttonActionHandler?(
                MappedActionInvocation(
                    actionID: actionID,
                    buttonID: buttonID,
                    kind: .horizontalScroll
                )
            )
        }
        if case let .transformed(transformed) = transformer.transform(output) {
            output = transformed
            shouldApply = true
        }
        guard shouldApply else { return }
        apply(output.vertical, to: event, axis: 1)
        apply(output.horizontal, to: event, axis: 2)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                state = CGEvent.tapIsEnabled(tap: tap)
                    ? .running
                    : .failed("CGEventTap 被系统停用")
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel {
            processScrollEvent(event)
        }
        if (type == .mouseMoved || type == .otherMouseDragged),
           let activeGestureButton
        {
            let directions = gestureRecognizer.sample(
                dx: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                dy: Double(event.getIntegerValueField(.mouseEventDeltaY)),
                source: .eventTap,
                at: ProcessInfo.processInfo.systemUptime
            )
            for direction in directions {
                let key = "\(activeGestureButton.configID)_\(direction.rawValue)"
                if let actionID = gestureMappings[key],
                   actionID != MouserAction.passThrough.rawValue
                {
                    buttonActionHandler?(
                        MappedActionInvocation(
                            actionID: actionID,
                            buttonID: activeGestureButton.configID,
                            kind: .gesture
                        )
                    )
                }
            }
            return nil
        }
        if type == .otherMouseDown || type == .otherMouseUp {
            let sample = MouseButtonSample(
                kind: type == .otherMouseDown ? .down : .up,
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                sourceUserData: event.getIntegerValueField(.eventSourceUserData)
            )
            let routedButton = MouseButtonEventRouter.button(for: sample.buttonNumber)
            if sample.kind == .down,
               let routedButton,
               buttonMappings[routedButton] == MouserAction.passThrough.rawValue {
                buttonActionHandler?(
                    MappedActionInvocation(
                        actionID: MouserAction.passThrough.rawValue,
                        buttonID: routedButton.configID,
                        kind: .press
                    )
                )
            }
            switch buttonRouter.route(sample) {
            case .passThrough:
                break
            case let .execute(actionID):
                if let routedButton {
                    buttonActionHandler?(
                        MappedActionInvocation(
                            actionID: actionID,
                            buttonID: routedButton.configID,
                            kind: .press
                        )
                    )
                }
                return nil
            case let .beginGesture(button):
                activeGestureButton = button
                gestureRecognizer.begin()
                return nil
            case let .endGesture(button):
                let wasClick = gestureRecognizer.end()
                activeGestureButton = nil
                if wasClick {
                    executeGestureMapping(for: button, slot: "tap")
                }
                return nil
            case .block:
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func executeGestureMapping(for button: MouseButton, slot: String) {
        let key = "\(button.configID)_\(slot)"
        guard let actionID = gestureMappings[key],
              actionID != MouserAction.passThrough.rawValue
        else { return }
        buttonActionHandler?(
            MappedActionInvocation(
                actionID: actionID,
                buttonID: button.configID,
                kind: .gesture
            )
        )
    }

    private func axisDeltas(in event: CGEvent, axis: Int) -> ScrollAxisDeltas {
        let fields = fields(for: axis)
        return ScrollAxisDeltas(
            line: event.getIntegerValueField(fields.line),
            fixed: event.getIntegerValueField(fields.fixed),
            point: event.getIntegerValueField(fields.point)
        )
    }

    private func horizontalButtonID(for deltas: ScrollAxisDeltas) -> String {
        let value = deltas.fixed != 0
            ? deltas.fixed
            : (deltas.line != 0 ? deltas.line : deltas.point)
        return value < 0 ? "hscroll_left" : "hscroll_right"
    }

    private func apply(_ deltas: ScrollAxisDeltas, to event: CGEvent, axis: Int) {
        let fields = fields(for: axis)
        event.setIntegerValueField(fields.line, value: deltas.line)
        event.setIntegerValueField(fields.fixed, value: deltas.fixed)
        event.setIntegerValueField(fields.point, value: deltas.point)
    }

    private func fields(for axis: Int) -> (
        line: CGEventField,
        fixed: CGEventField,
        point: CGEventField
    ) {
        if axis == 1 {
            return (
                .scrollWheelEventDeltaAxis1,
                .scrollWheelEventFixedPtDeltaAxis1,
                .scrollWheelEventPointDeltaAxis1
            )
        }
        return (
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventPointDeltaAxis2
        )
    }
}
