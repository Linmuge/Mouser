import CoreGraphics
import Testing
@testable import MouserNative

private final class ScrollActionCapture: @unchecked Sendable {
    var actionIDs: [String] = []
}

@Suite("Native scroll event transformation")
struct ScrollEventPipelineTests {
    @Test("vertical inversion preserves every horizontal representation")
    func verticalInversion() {
        let sample = ScrollSample(
            vertical: .init(line: 2, fixed: 131_072, point: 18),
            horizontal: .init(line: -1, fixed: -65_536, point: -9)
        )
        let transformer = ScrollEventTransformer(
            settings: .init(invertVertical: true, invertHorizontal: false, ignoreTrackpad: true)
        )

        let result = transformer.transform(sample)

        #expect(
            result == .transformed(
                ScrollSample(
                    vertical: .init(line: -2, fixed: -131_072, point: -18),
                    horizontal: sample.horizontal
                )
            )
        )
    }

    @Test("horizontal inversion negates all horizontal delta formats")
    func horizontalInversion() {
        let sample = ScrollSample(
            vertical: .init(line: 1, fixed: 65_536, point: 7),
            horizontal: .init(line: 3, fixed: 196_608, point: 21)
        )
        let transformer = ScrollEventTransformer(
            settings: .init(invertVertical: false, invertHorizontal: true, ignoreTrackpad: true)
        )

        let result = transformer.transform(sample)

        #expect(
            result == .transformed(
                ScrollSample(
                    vertical: sample.vertical,
                    horizontal: .init(line: -3, fixed: -196_608, point: -21)
                )
            )
        )
    }

    @Test("trackpad phases pass through when trackpad filtering is enabled")
    func trackpadPassesThrough() {
        let sample = ScrollSample(
            vertical: .init(line: 0, fixed: 32_768, point: 4),
            horizontal: .zero,
            scrollPhase: 1
        )
        let transformer = ScrollEventTransformer(
            settings: .init(invertVertical: true, invertHorizontal: true, ignoreTrackpad: true)
        )

        #expect(transformer.transform(sample) == .passThrough)
    }

    @Test("continuous events can be inverted when trackpad filtering is disabled")
    func continuousEventsCanBeIncluded() {
        let sample = ScrollSample(
            vertical: .init(line: 0, fixed: 32_768, point: 4),
            horizontal: .zero,
            momentumPhase: 2
        )
        let transformer = ScrollEventTransformer(
            settings: .init(invertVertical: true, invertHorizontal: false, ignoreTrackpad: false)
        )

        #expect(
            transformer.transform(sample) == .transformed(
                ScrollSample(
                    vertical: .init(line: 0, fixed: -32_768, point: -4),
                    horizontal: .zero,
                    momentumPhase: 2
                )
            )
        )
    }

    @Test("events emitted by Mouser are never transformed again")
    func markedEventsPassThrough() {
        let sample = ScrollSample(
            vertical: .init(line: 1, fixed: 65_536, point: 8),
            horizontal: .zero,
            sourceUserData: ScrollEventTransformer.eventMarker
        )
        let transformer = ScrollEventTransformer(
            settings: .init(invertVertical: true, invertHorizontal: true, ignoreTrackpad: false)
        )

        #expect(transformer.transform(sample) == .passThrough)
    }
}

@Suite("Horizontal scroll action routing")
struct HorizontalScrollActionRouterTests {
    private let leftMapping = ["hscroll_left": MouserAction.previousDesktop.rawValue]
    private let rightMapping = ["hscroll_right": MouserAction.nextDesktop.rawValue]

    @Test("fractional fixed-point deltas accumulate to the configured threshold")
    func accumulatesFractionalDeltas() {
        var router = HorizontalScrollActionRouter(threshold: 0.1)
        let sample = ScrollSample(
            vertical: .zero,
            horizontal: .init(line: 0, fixed: 2_294, point: 0)
        )

        let first = router.route(sample, mappings: rightMapping, uptime: 2)
        let second = router.route(sample, mappings: rightMapping, uptime: 2.02)
        let third = router.route(sample, mappings: rightMapping, uptime: 2.04)

        #expect(first == .consume)
        #expect(second == .consume)
        #expect(third == .execute(MouserAction.nextDesktop.rawValue))
    }

    @Test("positive and negative deltas use right and left mappings")
    func routesByDirection() {
        var router = HorizontalScrollActionRouter(threshold: 0.1)
        let mappings = leftMapping.merging(rightMapping) { _, rhs in rhs }
        let right = ScrollSample(
            vertical: .zero,
            horizontal: .init(line: 0, fixed: 6_554, point: 0)
        )
        let left = ScrollSample(
            vertical: .zero,
            horizontal: .init(line: 0, fixed: -6_554, point: 0)
        )

        #expect(
            router.route(right, mappings: mappings, uptime: 1)
                == .execute(MouserAction.nextDesktop.rawValue)
        )
        #expect(
            router.route(left, mappings: mappings, uptime: 2)
                == .execute(MouserAction.previousDesktop.rawValue)
        )
    }

    @Test("mapped events remain consumed during action cooldown")
    func cooldownConsumesWithoutRepeating() {
        var router = HorizontalScrollActionRouter(threshold: 0.1)
        let sample = ScrollSample(
            vertical: .zero,
            horizontal: .init(line: 0, fixed: 65_536, point: 0)
        )

        #expect(
            router.route(sample, mappings: rightMapping, uptime: 1)
                == .execute(MouserAction.nextDesktop.rawValue)
        )
        #expect(router.route(sample, mappings: rightMapping, uptime: 1.2) == .consume)
        #expect(
            router.route(sample, mappings: rightMapping, uptime: 1.36)
                == .execute(MouserAction.nextDesktop.rawValue)
        )
    }

    @Test("volume mappings use the shorter repeat cooldown")
    func volumeCooldown() {
        var router = HorizontalScrollActionRouter(threshold: 0.1)
        let mappings = ["hscroll_right": MouserAction.volumeUp.rawValue]
        let sample = ScrollSample(
            vertical: .zero,
            horizontal: .init(line: 0, fixed: 65_536, point: 0)
        )

        #expect(router.route(sample, mappings: mappings, uptime: 1) == .execute("volume_up"))
        #expect(router.route(sample, mappings: mappings, uptime: 1.04) == .consume)
        #expect(router.route(sample, mappings: mappings, uptime: 1.07) == .execute("volume_up"))
    }

    @Test("trackpad, marked, unmapped, and zero-delta events pass through")
    func ignoresUnrelatedEvents() {
        var router = HorizontalScrollActionRouter(threshold: 0.1)
        let horizontal = ScrollAxisDeltas(line: 1, fixed: 65_536, point: 8)

        #expect(
            router.route(
                ScrollSample(vertical: .zero, horizontal: horizontal, scrollPhase: 1),
                mappings: rightMapping,
                uptime: 1
            ) == .passThrough
        )
        #expect(
            router.route(
                ScrollSample(
                    vertical: .zero,
                    horizontal: horizontal,
                    sourceUserData: ScrollEventTransformer.eventMarker
                ),
                mappings: rightMapping,
                uptime: 1
            ) == .passThrough
        )
        #expect(
            router.route(
                ScrollSample(vertical: .zero, horizontal: horizontal),
                mappings: [:],
                uptime: 1
            ) == .passThrough
        )
        #expect(
            router.route(
                ScrollSample(vertical: .zero, horizontal: .zero),
                mappings: rightMapping,
                uptime: 1
            ) == .passThrough
        )
    }
}

@Suite("Session recovery scheduling")
struct SessionRecoveryPlannerTests {
    @Test("a session transition rearms immediately and with two bounded retries")
    func boundedRecovery() {
        var planner = SessionRecoveryPlanner()

        let delays = planner.schedule(for: .wake, uptime: .seconds(10))

        #expect(delays == [.zero, .seconds(1), .seconds(3)])
    }

    @Test("duplicate wake sources coalesce into one recovery sequence")
    func coalescesDuplicateSources() {
        var planner = SessionRecoveryPlanner()

        let first = planner.schedule(for: .screenWake, uptime: .seconds(10))
        let duplicate = planner.schedule(for: .screenUnlock, uptime: .milliseconds(10_600))
        let later = planner.schedule(for: .sessionActivated, uptime: .seconds(12))

        #expect(first == [.zero, .seconds(1), .seconds(3)])
        #expect(duplicate.isEmpty)
        #expect(later == [.zero, .seconds(1), .seconds(3)])
    }
}

@Suite("Core Graphics scroll bridge")
@MainActor
struct CoreGraphicsScrollBridgeTests {
    @Test("the event tap applies transformed values to the original Quartz event")
    func appliesTransformedValues() throws {
        let tap = CoreGraphicsScrollEventTap()
        tap.updateSettings(
            .init(invertVertical: true, invertHorizontal: false, ignoreTrackpad: true)
        )
        let event = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 2,
                wheel2: -1,
                wheel3: 0
            )
        )
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 131_072)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 18)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -65_536)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -9)

        tap.processScrollEvent(event)

        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -2)
        #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1) == -131_072)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -18)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -1)
        #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2) == -65_536)
    }

    @Test("trackpad events remain byte-for-byte unchanged")
    func preservesTrackpadEvents() throws {
        let tap = CoreGraphicsScrollEventTap()
        tap.updateSettings(
            .init(invertVertical: true, invertHorizontal: true, ignoreTrackpad: true)
        )
        let event = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 12,
                wheel2: 4,
                wheel3: 0
            )
        )
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)

        tap.processScrollEvent(event)

        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 12)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 4)
    }

    @Test("a mapped horizontal tilt executes once and clears only horizontal deltas")
    func consumesMappedHorizontalTilt() throws {
        let tap = CoreGraphicsScrollEventTap()
        let capture = ScrollActionCapture()
        tap.updateButtonMappings(
            [:],
            gestureMappings: ["hscroll_right": MouserAction.nextDesktop.rawValue]
        ) { invocation in
            capture.actionIDs.append(invocation.actionID)
        }
        let event = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 2,
                wheel2: 1,
                wheel3: 0
            )
        )
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 131_072)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 18)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 65_536)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 9)

        tap.processScrollEvent(event, uptime: 1)

        #expect(capture.actionIDs == [MouserAction.nextDesktop.rawValue])
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 2)
        #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1) == 131_072)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0)
        #expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0)
    }
}

@Suite("Console lock edge detection")
struct ConsoleLockTransitionDetectorTests {
    @Test("only a locked to unlocked edge requests recovery")
    func detectsUnlockEdge() {
        var detector = ConsoleLockTransitionDetector()

        let unavailable = detector.observe(nil)
        let initiallyUnlocked = detector.observe(false)
        let locked = detector.observe(true)
        let stillLocked = detector.observe(true)
        let unlocked = detector.observe(false)
        let stillUnlocked = detector.observe(false)

        #expect(!unavailable)
        #expect(!initiallyUnlocked)
        #expect(!locked)
        #expect(!stillLocked)
        #expect(unlocked)
        #expect(!stillUnlocked)
    }
}
