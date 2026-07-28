import Testing
@testable import MouserNative

@Suite("macOS action execution")
struct MacActionExecutorTests {
    @Test("native catalog preserves every macOS action from the Python app")
    func catalogPreservesPythonActions() {
        let expected = Set([
            "alt_tab", "alt_shift_tab", "browser_back", "browser_forward",
            "copy", "paste", "cut", "undo", "select_all", "save", "next_tab",
            "prev_tab", "close_tab", "new_tab", "find", "win_d", "task_view",
            "mission_control", "app_expose", "space_left", "space_right",
            "cycle_desktops", "show_desktop", "launchpad", "volume_up",
            "volume_down", "volume_mute", "play_pause", "next_track", "prev_track",
            "zoom_in", "zoom_out", "page_up", "page_down", "home", "end",
            "switch_scroll_mode", "toggle_smart_shift", "cycle_dpi",
            "activate_actions_ring", "mouse_left_click", "mouse_right_click",
            "mouse_middle_click", "mouse_back_click", "mouse_forward_click",
            "screenshot_region_clip", "screenshot_region_file",
            "screenshot_full_clip", "screenshot_full_file", "none",
        ])

        #expect(Set(MouserAction.allCases.map(\.rawValue)) == expected)
    }

    @Test("standard shortcuts produce the same macOS key chords")
    func standardShortcutPlans() {
        #expect(
            MacActionPlanner.plan(for: "paste") ==
                .keyboard(keys: [.command, .v], repetitions: 1)
        )
        #expect(
            MacActionPlanner.plan(for: "screenshot_region_clip") ==
                .keyboard(keys: [.command, .shift, .control, .four], repetitions: 1)
        )
        #expect(
            MacActionPlanner.plan(for: "zoom_in") ==
                .keyboard(keys: [.command, .equal], repetitions: 3)
        )
    }

    @Test("custom shortcuts accept legacy names and reject unknown keys")
    func customShortcutPlans() {
        #expect(
            MacActionPlanner.plan(for: "custom:ctrl+shift+f12") ==
                .keyboard(keys: [.control, .shift, .f12], repetitions: 1)
        )
        #expect(
            MacActionPlanner.plan(for: "custom:super+alt+left") ==
                .keyboard(keys: [.command, .option, .leftArrow], repetitions: 1)
        )
        #expect(MacActionPlanner.plan(for: "custom:super+definitely-not-a-key") == nil)
    }

    @Test("captured shortcuts use Python-compatible order and macOS labels")
    func customShortcutCaptureModel() {
        let shortcut = CustomShortcut(
            modifiers: ["super", "ctrl", "shift"],
            key: "k"
        )

        #expect(shortcut?.actionID == "custom:ctrl+shift+super+k")
        #expect(shortcut?.displayText == "⌃⇧⌘K")
        #expect(CustomShortcut(actionID: "custom:super+alt+left")?.displayText == "⌥⌘←")
        #expect(CustomShortcut(modifiers: ["super"], key: "unknown") == nil)
        #expect(CustomShortcut(actionID: "copy") == nil)
    }

    @Test("mouse media and engine-owned actions remain distinguishable")
    func specializedActionPlans() {
        #expect(MacActionPlanner.plan(for: "mouse_back_click") == .mouse(button: 3))
        #expect(MacActionPlanner.plan(for: "play_pause") == .media(.playPause))
        #expect(MacActionPlanner.plan(for: "switch_scroll_mode") == .engine(.switchScrollMode))
        #expect(MacActionPlanner.plan(for: "none") == .noOp)
        #expect(MacActionPlanner.plan(for: "unknown-action") == nil)
    }
}
