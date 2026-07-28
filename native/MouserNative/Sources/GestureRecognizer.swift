import Foundation

enum ActionsRingEffect: Equatable, Sendable {
    case show(interactive: Bool)
    case hide
    case highlight(Int?)
    case execute(String)
    case haptic(Int)
}

struct ActionsRingStateMachine: Sendable {
    enum State: Equatable, Sendable {
        case idle
        case waiting
        case showingHeld
        case showingToggle
    }

    var slots: [String]
    var holdMilliseconds: Int
    private(set) var state: State = .idle
    private(set) var selectedSector: Int?
    private var accumulatedX = 0.0
    private var accumulatedY = 0.0

    mutating func buttonDown() -> [ActionsRingEffect] {
        switch state {
        case .idle:
            state = .waiting
            selectedSector = nil
            accumulatedX = 0
            accumulatedY = 0
            return []
        case .showingToggle:
            state = .idle
            selectedSector = nil
            return [.hide]
        case .waiting, .showingHeld:
            return []
        }
    }

    mutating func holdElapsed() -> [ActionsRingEffect] {
        guard state == .waiting else { return [] }
        state = .showingHeld
        return [.show(interactive: false), .haptic(0)]
    }

    mutating func buttonUp() -> [ActionsRingEffect] {
        switch state {
        case .waiting:
            state = .showingToggle
            return [.show(interactive: true), .haptic(0)]
        case .showingHeld:
            state = .idle
            defer { selectedSector = nil }
            guard let selectedSector, slots.indices.contains(selectedSector) else {
                return [.hide]
            }
            return [.hide, .execute(slots[selectedSector]), .haptic(7)]
        case .showingToggle, .idle:
            return []
        }
    }

    mutating func toggle() -> [ActionsRingEffect] {
        switch state {
        case .idle:
            state = .showingToggle
            selectedSector = nil
            return [.show(interactive: true), .haptic(0)]
        case .showingToggle, .showingHeld, .waiting:
            state = .idle
            selectedSector = nil
            return [.hide]
        }
    }

    mutating func move(dx: Int16, dy: Int16) -> [ActionsRingEffect] {
        guard state == .showingHeld else { return [] }
        accumulatedX += Double(dx)
        accumulatedY += Double(dy)
        let newSector = Self.sector(
            dx: accumulatedX,
            dy: accumulatedY,
            count: slots.count
        )
        guard newSector != selectedSector else { return [] }
        selectedSector = newSector
        return [.highlight(newSector)]
    }

    mutating func selectToggleSector(_ sector: Int) -> [ActionsRingEffect] {
        guard state == .showingToggle else { return [] }
        state = .idle
        selectedSector = nil
        guard slots.indices.contains(sector) else { return [.hide] }
        return [.hide, .execute(slots[sector]), .haptic(7)]
    }

    mutating func dismiss() -> [ActionsRingEffect] {
        guard state == .showingToggle || state == .showingHeld else { return [] }
        state = .idle
        selectedSector = nil
        return [.hide]
    }

    static func sector(dx: Double, dy: Double, count: Int) -> Int? {
        guard count > 0, hypot(dx, dy) >= 30 else { return nil }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let sectorSize = 360 / Double(count)
        return Int((degrees + sectorSize / 2).truncatingRemainder(dividingBy: 360) / sectorSize)
    }
}

enum GestureDirection: String, CaseIterable, Equatable, Sendable {
    case left
    case right
    case up
    case down

    var axis: GestureAxis {
        switch self {
        case .left, .right: .x
        case .up, .down: .y
        }
    }

    var sign: Double {
        switch self {
        case .left, .up: -1
        case .right, .down: 1
        }
    }
}

enum GestureSampleSource: Equatable, Sendable {
    case eventTap
    case hidRawXY
}

enum GestureAxis: Sendable {
    case x
    case y
}

struct GestureRecognizer: Sendable {
    private enum Phase: Sendable {
        case idle
        case locked
    }

    private static let crossFloor = 14.0
    private static let refractory = 0.09
    private static let turnHysteresis = 4.0
    private static let minimumSamples = 4

    private var enabled: Bool
    private var commitDistance: Double
    private var commitWindow: Double
    private var settle: Double
    private var crossRatio: Double
    private var directionEpsilon: Double
    private var minimumReturn: Double

    private var phase: Phase = .idle
    private var active = false
    private var firedAny = false
    private var source: GestureSampleSource?
    private var lastTime: Double?
    private var lastFireTime = -Double.infinity
    private var currentX = 0.0
    private var currentY = 0.0
    private var pivotX = 0.0
    private var pivotY = 0.0
    private var pivotTime: Double?
    private var legPeak = 0.0
    private var legSamples = 0
    private var lockAxis: GestureAxis?
    private var lockSign = 0.0
    private var latchAnchor = 0.0
    private var latchExtreme = 0.0
    private var latchOffAtTurn = 0.0
    private var latchTurnTime = 0.0
    private var latchReturnSeen = false

    init(
        enabled: Bool = true,
        threshold: Double = 50,
        commitWindowMilliseconds: Double = 400,
        settleMilliseconds: Double = 90,
        crossRatio: Double = 0.5
    ) {
        self.enabled = enabled
        commitDistance = max(8, threshold)
        commitWindow = max(0.05, commitWindowMilliseconds / 1_000)
        settle = max(0.02, settleMilliseconds / 1_000)
        self.crossRatio = min(2, max(0.05, crossRatio))
        directionEpsilon = max(5, commitDistance * 0.15)
        minimumReturn = max(14, commitDistance * 0.45)
    }

    mutating func begin() {
        resetHold()
        active = true
    }

    mutating func end() -> Bool {
        let wasClick = active && !firedAny
        active = false
        phase = .idle
        return wasClick
    }

    mutating func sample(
        dx: Double,
        dy: Double,
        source: GestureSampleSource = .hidRawXY,
        at time: Double
    ) -> [GestureDirection] {
        guard active, enabled, dx != 0 || dy != 0, accept(source: source) else { return [] }
        if let lastTime, time - lastTime > settle {
            phase = .idle
            lockAxis = nil
            lockSign = 0
            resetLeg(atX: currentX, y: currentY)
        }
        lastTime = time
        currentX += dx
        currentY += dy

        switch phase {
        case .idle:
            return stepFree(at: time)
        case .locked:
            return stepLocked(at: time)
        }
    }

    private mutating func resetHold() {
        phase = .idle
        active = false
        firedAny = false
        source = nil
        lastTime = nil
        lastFireTime = -Double.infinity
        currentX = 0
        currentY = 0
        resetLeg(atX: 0, y: 0)
        lockAxis = nil
        lockSign = 0
        latchAnchor = 0
        latchExtreme = 0
        latchOffAtTurn = 0
        latchTurnTime = 0
        latchReturnSeen = false
    }

    private mutating func resetLeg(atX x: Double, y: Double) {
        pivotX = x
        pivotY = y
        pivotTime = nil
        legPeak = 0
        legSamples = 0
    }

    private mutating func accept(source newSource: GestureSampleSource) -> Bool {
        if source == newSource { return true }
        if source == nil {
            source = newSource
            return true
        }
        if newSource == .hidRawXY {
            source = newSource
            phase = .idle
            lockAxis = nil
            lockSign = 0
            resetLeg(atX: currentX, y: currentY)
            return true
        }
        return false
    }

    private mutating func stepFree(at time: Double) -> [GestureDirection] {
        let legX = currentX - pivotX
        let legY = currentY - pivotY
        let legLength = hypot(legX, legY)

        if pivotTime == nil {
            guard legLength >= directionEpsilon else { return [] }
            pivotTime = time
            legPeak = legLength
            legSamples = 1
        } else {
            legSamples += 1
        }

        if legLength < legPeak - directionEpsilon {
            resetLeg(atX: currentX, y: currentY)
            return []
        }
        legPeak = max(legPeak, legLength)

        guard let pivotTime else { return [] }
        if time - pivotTime > commitWindow {
            resetLeg(atX: currentX, y: currentY)
            return []
        }
        guard let direction = evaluate(legX: legX, legY: legY),
              legSamples >= Self.minimumSamples,
              fire(direction, at: time)
        else { return [] }

        phase = .locked
        lockAxis = direction.axis
        lockSign = direction.sign
        let position = direction.axis == .x ? currentX : currentY
        let offAxis = direction.axis == .x ? currentY : currentX
        latchAnchor = position
        latchExtreme = position
        latchOffAtTurn = offAxis
        latchTurnTime = time
        latchReturnSeen = false
        return [direction]
    }

    private mutating func stepLocked(at time: Double) -> [GestureDirection] {
        guard let lockAxis else { return [] }
        let position = lockAxis == .x ? currentX : currentY
        let offAxis = lockAxis == .x ? currentY : currentX

        if lockSign * position < lockSign * latchExtreme - Self.turnHysteresis {
            latchExtreme = position
            latchOffAtTurn = offAxis
            latchTurnTime = time
        }
        let returnAmount = lockSign * (latchAnchor - latchExtreme)
        if returnAmount >= minimumReturn {
            latchReturnSeen = true
        }

        let flick = lockSign * (position - latchExtreme)
        let offFlick = offAxis - latchOffAtTurn
        guard latchReturnSeen, flick >= commitDistance else { return [] }
        if time - latchTurnTime > commitWindow {
            resetLatch(position: position, offAxis: offAxis, at: time)
            return []
        }
        guard abs(offFlick) <= crossRatio * flick + Self.crossFloor else { return [] }

        let direction: GestureDirection = switch (lockAxis, lockSign > 0) {
        case (.x, true): .right
        case (.x, false): .left
        case (.y, true): .down
        case (.y, false): .up
        }
        guard fire(direction, at: time) else { return [] }
        resetLatch(position: position, offAxis: offAxis, at: time)
        return [direction]
    }

    private func evaluate(legX: Double, legY: Double) -> GestureDirection? {
        let absX = abs(legX)
        let absY = abs(legY)
        let dominant: Double
        let cross: Double
        let direction: GestureDirection
        if absX >= absY {
            dominant = absX
            cross = absY
            direction = legX > 0 ? .right : .left
        } else {
            dominant = absY
            cross = absX
            direction = legY > 0 ? .down : .up
        }
        guard dominant >= commitDistance,
              cross <= crossRatio * dominant + Self.crossFloor
        else { return nil }
        return direction
    }

    private mutating func fire(_ direction: GestureDirection, at time: Double) -> Bool {
        _ = direction
        guard time - lastFireTime >= Self.refractory else { return false }
        lastFireTime = time
        firedAny = true
        return true
    }

    private mutating func resetLatch(position: Double, offAxis: Double, at time: Double) {
        latchAnchor = position
        latchExtreme = position
        latchOffAtTurn = offAxis
        latchTurnTime = time
        latchReturnSeen = false
    }
}
