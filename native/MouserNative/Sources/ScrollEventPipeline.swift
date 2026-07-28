import Foundation

struct ScrollAxisDeltas: Equatable, Sendable {
    var line: Int64
    var fixed: Int64
    var point: Int64

    static let zero = ScrollAxisDeltas(line: 0, fixed: 0, point: 0)

    func negated() -> ScrollAxisDeltas {
        ScrollAxisDeltas(line: -line, fixed: -fixed, point: -point)
    }
}

struct ScrollSample: Equatable, Sendable {
    var vertical: ScrollAxisDeltas
    var horizontal: ScrollAxisDeltas
    var scrollPhase: Int64
    var momentumPhase: Int64
    var sourceUserData: Int64

    init(
        vertical: ScrollAxisDeltas,
        horizontal: ScrollAxisDeltas,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        sourceUserData: Int64 = 0
    ) {
        self.vertical = vertical
        self.horizontal = horizontal
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.sourceUserData = sourceUserData
    }
}

struct ScrollInversionSettings: Equatable, Sendable {
    var invertVertical: Bool
    var invertHorizontal: Bool
    var ignoreTrackpad: Bool
}

struct GestureRecognitionSettings: Equatable, Sendable {
    var threshold: Double
    var commitWindowMilliseconds: Double
    var settleMilliseconds: Double
    var crossRatio: Double
}

enum ScrollTransformDecision: Equatable, Sendable {
    case passThrough
    case transformed(ScrollSample)
}

enum HorizontalScrollRoutingDecision: Equatable, Sendable {
    case passThrough
    case consume
    case execute(String)
}

struct HorizontalScrollActionRouter: Sendable {
    static let shiftWheelEventMarker: Int64 = 0x4D4F5556

    private struct DirectionState: Sendable {
        var accumulatedDelta = 0.0
        var lastExecutionUptime: TimeInterval?
    }

    var threshold: Double
    private var states: [String: DirectionState] = [:]

    init(threshold: Double = 0.1) {
        self.threshold = max(0.01, threshold)
    }

    mutating func route(
        _ sample: ScrollSample,
        mappings: [String: String],
        uptime: TimeInterval
    ) -> HorizontalScrollRoutingDecision {
        guard sample.scrollPhase == 0,
              sample.momentumPhase == 0,
              sample.sourceUserData != ScrollEventTransformer.eventMarker,
              sample.sourceUserData != Self.shiftWheelEventMarker,
              let directionKey = directionKey(for: sample.horizontal),
              let actionID = mappings[directionKey],
              actionID != MouserAction.passThrough.rawValue
        else {
            return .passThrough
        }

        var state = states[directionKey] ?? DirectionState()
        let cooldown = actionID == MouserAction.volumeUp.rawValue ||
            actionID == MouserAction.volumeDown.rawValue ? 0.06 : 0.35
        if let lastExecutionUptime = state.lastExecutionUptime,
           uptime - lastExecutionUptime < cooldown {
            state.accumulatedDelta = 0
            states[directionKey] = state
            return .consume
        }

        state.accumulatedDelta += min(step(for: sample.horizontal), 1)
        guard state.accumulatedDelta >= max(0.01, threshold) else {
            states[directionKey] = state
            return .consume
        }

        state.accumulatedDelta = 0
        state.lastExecutionUptime = uptime
        states[directionKey] = state
        return .execute(actionID)
    }

    private func directionKey(for deltas: ScrollAxisDeltas) -> String? {
        let signedValue: Double
        if deltas.fixed != 0 {
            signedValue = Double(deltas.fixed)
        } else if deltas.line != 0 {
            signedValue = Double(deltas.line)
        } else {
            signedValue = Double(deltas.point)
        }
        guard signedValue != 0 else { return nil }
        return signedValue > 0 ? "hscroll_right" : "hscroll_left"
    }

    private func step(for deltas: ScrollAxisDeltas) -> Double {
        if deltas.fixed != 0 {
            return abs(Double(deltas.fixed) / 65_536)
        }
        if deltas.line != 0 {
            return abs(Double(deltas.line))
        }
        return abs(Double(deltas.point))
    }
}

struct ScrollEventTransformer: Sendable {
    static let eventMarker: Int64 = 0x4D4F5553

    var settings: ScrollInversionSettings

    func transform(_ sample: ScrollSample) -> ScrollTransformDecision {
        guard sample.sourceUserData != Self.eventMarker else {
            return .passThrough
        }
        if settings.ignoreTrackpad,
           sample.scrollPhase != 0 || sample.momentumPhase != 0 {
            return .passThrough
        }
        guard settings.invertVertical || settings.invertHorizontal else {
            return .passThrough
        }

        var transformed = sample
        if settings.invertVertical {
            transformed.vertical = transformed.vertical.negated()
        }
        if settings.invertHorizontal {
            transformed.horizontal = transformed.horizontal.negated()
        }
        return .transformed(transformed)
    }
}

enum SessionRecoverySignal: Equatable, Sendable {
    case wake
    case screenWake
    case sessionActivated
    case screenUnlock
    case deviceActivity
}

struct SessionRecoveryPlanner: Sendable {
    private static let retryDelays: [Duration] = [
        .zero,
        .seconds(1),
        .seconds(3),
    ]

    private var lastRecoveryUptime: Duration?
    private var awaitsHIDSettingsRestore = false
    private let coalescingWindow: Duration

    init(coalescingWindow: Duration = .seconds(1)) {
        self.coalescingWindow = coalescingWindow
    }

    mutating func schedule(
        for signal: SessionRecoverySignal,
        uptime: Duration
    ) -> [Duration] {
        if signal == .deviceActivity {
            return awaitsHIDSettingsRestore ? [.zero] : []
        }
        awaitsHIDSettingsRestore = true
        if let lastRecoveryUptime,
           uptime - lastRecoveryUptime < coalescingWindow {
            return []
        }
        lastRecoveryUptime = uptime
        return Self.retryDelays
    }

    mutating func markHIDSettingsRestored() {
        awaitsHIDSettingsRestore = false
    }
}

struct ConsoleLockTransitionDetector: Sendable {
    private var previousState: Bool?

    mutating func observe(_ isLocked: Bool?) -> Bool {
        guard let isLocked else { return false }
        defer { previousState = isLocked }
        return previousState == true && !isLocked
    }
}
