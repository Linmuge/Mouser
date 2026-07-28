import Testing
@testable import MouserNative

@Suite("Actions Ring interaction")
struct ActionsRingStateMachineTests {
    @Test("sector geometry starts at the top and advances clockwise")
    func sectorGeometry() {
        #expect(ActionsRingStateMachine.sector(dx: 0, dy: -60, count: 4) == 0)
        #expect(ActionsRingStateMachine.sector(dx: 60, dy: 0, count: 4) == 1)
        #expect(ActionsRingStateMachine.sector(dx: 0, dy: 60, count: 4) == 2)
        #expect(ActionsRingStateMachine.sector(dx: -60, dy: 0, count: 4) == 3)
        #expect(ActionsRingStateMachine.sector(dx: 10, dy: 10, count: 4) == nil)
    }

    @Test("quick tap opens toggle mode and a slot click executes it")
    func quickTapToggleMode() {
        var ring = ActionsRingStateMachine(slots: ["copy", "paste"], holdMilliseconds: 250)

        #expect(ring.buttonDown() == [])
        #expect(ring.buttonUp() == [.show(interactive: true), .haptic(0)])
        #expect(ring.state == .showingToggle)
        #expect(ring.selectToggleSector(1) == [.hide, .execute("paste"), .haptic(7)])
        #expect(ring.state == .idle)
    }

    @Test("holding opens held mode, movement highlights, and release commits")
    func heldMode() {
        var ring = ActionsRingStateMachine(
            slots: ["mission_control", "play_pause", "show_desktop", "launchpad"],
            holdMilliseconds: 250
        )

        _ = ring.buttonDown()
        #expect(ring.holdElapsed() == [.show(interactive: false), .haptic(0)])
        #expect(ring.move(dx: 70, dy: 0) == [.highlight(1)])
        #expect(ring.buttonUp() == [.hide, .execute("play_pause"), .haptic(7)])
        #expect(ring.state == .idle)
    }

    @Test("release in the dead zone dismisses without executing")
    func deadZoneDismisses() {
        var ring = ActionsRingStateMachine(slots: ["copy"], holdMilliseconds: 250)

        _ = ring.buttonDown()
        _ = ring.holdElapsed()

        #expect(ring.buttonUp() == [.hide])
    }
}

@Suite("stroke-aware gesture recognition")
struct GestureRecognizerTests {
    @Test("each cardinal flick is recognized and release is no longer a click", arguments: [
        (Self.flickLeft, GestureDirection.left),
        (Self.flickRight, GestureDirection.right),
        (Self.flickUp, GestureDirection.up),
        (Self.flickDown, GestureDirection.down),
    ])
    func cardinalDirections(samples: [(Double, Double)], expected: GestureDirection) {
        var recognizer = GestureRecognizer()
        recognizer.begin()
        let directions = Self.feed(&recognizer, samples, start: 0).directions
        let wasClick = recognizer.end()

        #expect(directions == [expected])
        #expect(!wasClick)
    }

    @Test("slow drift, tiny motion, steep diagonal, and click jolts are rejected")
    func rejectsFalsePositives() {
        for samples in [
            Array(repeating: (-1.0, 0.0), count: 70),
            Array(repeating: (-6.0, 0.0), count: 5),
            Array(repeating: (-9.0, -9.0), count: 8),
            [(-34.0, 0.0), (-34.0, 0.0)],
            [(-95.0, 5.0)],
        ] {
            var recognizer = GestureRecognizer()
            recognizer.begin()
            let directions = Self.feed(&recognizer, samples, start: 0).directions
            let wasClick = recognizer.end()
            #expect(directions.isEmpty)
            #expect(wasClick)
        }
    }

    @Test("return strokes rearm repeated flicks without firing the opposite direction")
    func repeatedFlicks() {
        var recognizer = GestureRecognizer()
        recognizer.begin()
        var time = 0.0
        var directions: [GestureDirection] = []
        for samples in [Self.flickLeft, Self.flickRight, Self.flickLeft, Self.flickRight, Self.flickLeft] {
            let result = Self.feed(&recognizer, samples, start: time)
            time = result.time
            directions += result.directions
        }
        let wasClick = recognizer.end()

        #expect(directions == [.left, .left, .left])
        #expect(!wasClick)
    }

    @Test("a pause clears direction lock and permits another direction")
    func pauseClearsDirectionLock() {
        var recognizer = GestureRecognizer()
        recognizer.begin()
        let first = Self.feed(&recognizer, Self.flickLeft, start: 0)
        let second = Self.feed(
            &recognizer,
            Self.flickRight,
            start: first.time,
            firstGap: 0.2
        )

        #expect(first.directions + second.directions == [.left, .right])
    }

    @Test("HID raw movement supersedes event tap movement during one hold")
    func rawXYTakesPriority() {
        var recognizer = GestureRecognizer()
        recognizer.begin()
        let partial = Self.feed(
            &recognizer,
            Array(repeating: (-10.0, 0.0), count: 4),
            start: 0,
            source: .eventTap
        )
        let raw = Self.feed(
            &recognizer,
            Self.flickLeft,
            start: partial.time,
            source: .hidRawXY
        )
        let ignored = recognizer.sample(
            dx: -40,
            dy: 0,
            source: .eventTap,
            at: raw.time + 0.012
        )

        #expect(raw.directions == [.left])
        #expect(ignored.isEmpty)
    }

    private static let flickLeft = Array(repeating: (-10.0, 0.0), count: 7)
    private static let flickRight = Array(repeating: (10.0, 0.0), count: 7)
    private static let flickUp = Array(repeating: (0.0, -10.0), count: 7)
    private static let flickDown = Array(repeating: (0.0, 10.0), count: 7)

    @discardableResult
    private static func feed(
        _ recognizer: inout GestureRecognizer,
        _ samples: [(Double, Double)],
        start: Double,
        step: Double = 0.012,
        firstGap: Double? = nil,
        source: GestureSampleSource = .hidRawXY
    ) -> (directions: [GestureDirection], time: Double) {
        var time = start
        var directions: [GestureDirection] = []
        for (index, sample) in samples.enumerated() {
            time += index == 0 ? (firstGap ?? step) : step
            directions += recognizer.sample(
                dx: sample.0,
                dy: sample.1,
                source: source,
                at: time
            )
        }
        return (directions, time)
    }
}
