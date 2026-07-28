import Testing
@testable import MouserNative

@Suite("mouse button event routing")
struct MouseButtonEventRouterTests {
    @Test("mapped button fires once on press and swallows its matching release")
    func mappedButtonLifecycle() {
        var router = MouseButtonEventRouter(mappings: [.back: "paste"])

        #expect(router.route(.init(kind: .down, buttonNumber: 3)) == .execute("paste"))
        #expect(router.route(.init(kind: .up, buttonNumber: 3)) == .block)
    }

    @Test("pass-through unknown and injected buttons remain untouched")
    func passThroughCases() {
        var router = MouseButtonEventRouter(mappings: [
            .middle: MouserAction.passThrough.rawValue,
            .back: MouserAction.mouseForward.rawValue,
        ])

        #expect(router.route(.init(kind: .down, buttonNumber: 2)) == .passThrough)
        #expect(router.route(.init(kind: .down, buttonNumber: 8)) == .passThrough)
        #expect(router.route(.init(
            kind: .down,
            buttonNumber: 3,
            sourceUserData: MouseButtonSample.injectedEventMarker
        )) == .passThrough)
    }

    @Test("replacing mappings releases stale swallowed state")
    func mappingsCanBeReloaded() {
        var router = MouseButtonEventRouter(mappings: [.forward: "copy"])
        #expect(router.route(.init(kind: .down, buttonNumber: 4)) == .execute("copy"))

        router.updateMappings([.forward: MouserAction.passThrough.rawValue])

        #expect(router.route(.init(kind: .up, buttonNumber: 4)) == .passThrough)
    }

    @Test("gesture sentinel arms and resolves the owning physical button")
    func gestureLifecycle() {
        var router = MouseButtonEventRouter(mappings: [.back: "gesture_swipe"])

        #expect(router.route(.init(kind: .down, buttonNumber: 3)) == .beginGesture(.back))
        #expect(router.route(.init(kind: .up, buttonNumber: 3)) == .endGesture(.back))
    }
}
