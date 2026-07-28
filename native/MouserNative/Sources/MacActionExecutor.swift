import AppKit
import CoreGraphics
import Foundation

enum MouserActionCategory: String, CaseIterable, Sendable {
    case navigation
    case browser
    case editing
    case media
    case mouse
    case screenshot
    case scroll
    case other

    var title: String {
        switch self {
        case .navigation: "导航"
        case .browser: "浏览器"
        case .editing: "编辑"
        case .media: "媒体"
        case .mouse: "鼠标"
        case .screenshot: "截屏"
        case .scroll: "滚动"
        case .other: "其他"
        }
    }
}

enum MouserAction: String, CaseIterable, Identifiable, Sendable {
    case switchWindows = "alt_tab"
    case switchWindowsReverse = "alt_shift_tab"
    case browserBack = "browser_back"
    case browserForward = "browser_forward"
    case copy
    case paste
    case cut
    case undo
    case selectAll = "select_all"
    case save
    case nextTab = "next_tab"
    case previousTab = "prev_tab"
    case closeTab = "close_tab"
    case newTab = "new_tab"
    case find
    case legacyShowDesktop = "win_d"
    case legacyTaskView = "task_view"
    case missionControl = "mission_control"
    case appExpose = "app_expose"
    case previousDesktop = "space_left"
    case nextDesktop = "space_right"
    case cycleDesktops = "cycle_desktops"
    case showDesktop = "show_desktop"
    case launchpad
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case volumeMute = "volume_mute"
    case playPause = "play_pause"
    case nextTrack = "next_track"
    case previousTrack = "prev_track"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case pageUp = "page_up"
    case pageDown = "page_down"
    case home
    case end
    case switchScrollMode = "switch_scroll_mode"
    case toggleSmartShift = "toggle_smart_shift"
    case cycleDPI = "cycle_dpi"
    case activateActionsRing = "activate_actions_ring"
    case mouseLeft = "mouse_left_click"
    case mouseRight = "mouse_right_click"
    case mouseMiddle = "mouse_middle_click"
    case mouseBack = "mouse_back_click"
    case mouseForward = "mouse_forward_click"
    case screenshotRegionClipboard = "screenshot_region_clip"
    case screenshotRegionFile = "screenshot_region_file"
    case screenshotFullClipboard = "screenshot_full_clip"
    case screenshotFullFile = "screenshot_full_file"
    case passThrough = "none"

    var id: Self { self }

    var category: MouserActionCategory {
        switch self {
        case .browserBack, .browserForward, .nextTab, .previousTab, .closeTab, .newTab:
            .browser
        case .copy, .paste, .cut, .undo, .selectAll, .save, .find:
            .editing
        case .volumeUp, .volumeDown, .volumeMute, .playPause, .nextTrack, .previousTrack:
            .media
        case .mouseLeft, .mouseRight, .mouseMiddle, .mouseBack, .mouseForward:
            .mouse
        case .screenshotRegionClipboard, .screenshotRegionFile,
             .screenshotFullClipboard, .screenshotFullFile:
            .screenshot
        case .switchScrollMode, .toggleSmartShift, .cycleDPI:
            .scroll
        case .activateActionsRing, .passThrough:
            .other
        default:
            .navigation
        }
    }

    var title: String {
        switch self {
        case .switchWindows: "切换应用（⌘Tab）"
        case .switchWindowsReverse: "反向切换应用（⌘⇧Tab）"
        case .browserBack: "浏览器后退"
        case .browserForward: "浏览器前进"
        case .copy: "复制"
        case .paste: "粘贴"
        case .cut: "剪切"
        case .undo: "撤销"
        case .selectAll: "全选"
        case .save: "保存"
        case .nextTab: "下一个标签页"
        case .previousTab: "上一个标签页"
        case .closeTab: "关闭标签页"
        case .newTab: "新建标签页"
        case .find: "查找"
        case .legacyShowDesktop, .legacyTaskView, .missionControl: "调度中心"
        case .appExpose: "应用程序窗口"
        case .previousDesktop: "上一个桌面"
        case .nextDesktop: "下一个桌面"
        case .cycleDesktops: "循环切换桌面"
        case .showDesktop: "显示桌面"
        case .launchpad: "启动台"
        case .volumeUp: "增大音量"
        case .volumeDown: "减小音量"
        case .volumeMute: "静音"
        case .playPause: "播放 / 暂停"
        case .nextTrack: "下一首"
        case .previousTrack: "上一首"
        case .zoomIn: "放大"
        case .zoomOut: "缩小"
        case .pageUp: "向上翻页"
        case .pageDown: "向下翻页"
        case .home: "移到开头"
        case .end: "移到结尾"
        case .switchScrollMode: "切换棘轮 / 飞轮"
        case .toggleSmartShift: "切换 SmartShift"
        case .cycleDPI: "循环切换 DPI"
        case .activateActionsRing: "操作环"
        case .mouseLeft: "鼠标左键"
        case .mouseRight: "鼠标右键"
        case .mouseMiddle: "鼠标中键"
        case .mouseBack: "鼠标后退"
        case .mouseForward: "鼠标前进"
        case .screenshotRegionClipboard: "截取区域到剪贴板"
        case .screenshotRegionFile: "截取区域到文件"
        case .screenshotFullClipboard: "截取全屏到剪贴板"
        case .screenshotFullFile: "截取全屏到文件"
        case .passThrough: "不执行操作"
        }
    }
}

enum MacVirtualKey: UInt16, Equatable, Sendable {
    case a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05
    case z = 0x06, x = 0x07, c = 0x08, v = 0x09, b = 0x0B, q = 0x0C
    case w = 0x0D, e = 0x0E, r = 0x0F, y = 0x10, t = 0x11
    case one = 0x12, two = 0x13, three = 0x14, four = 0x15, six = 0x16
    case five = 0x17, equal = 0x18, nine = 0x19, seven = 0x1A
    case minus = 0x1B, eight = 0x1C, zero = 0x1D, rightBracket = 0x1E
    case o = 0x1F, u = 0x20, leftBracket = 0x21, i = 0x22, p = 0x23
    case returnKey = 0x24, l = 0x25, j = 0x26, quote = 0x27, k = 0x28, semicolon = 0x29
    case backslash = 0x2A, comma = 0x2B, slash = 0x2C, n = 0x2D, m = 0x2E
    case period = 0x2F, tab = 0x30, space = 0x31, grave = 0x32
    case backspace = 0x33, escape = 0x35, command = 0x37, shift = 0x38
    case capsLock = 0x39, option = 0x3A, control = 0x3B, rightShift = 0x3C
    case rightOption = 0x3D, rightControl = 0x3E, function = 0x3F
    case f17 = 0x40, volumeUp = 0x48, volumeDown = 0x49, mute = 0x4A
    case f18 = 0x4F, f19 = 0x50, f20 = 0x5A, f5 = 0x60, f6 = 0x61
    case f7 = 0x62, f3 = 0x63, f8 = 0x64, f9 = 0x65, f11 = 0x67
    case f13 = 0x69, f16 = 0x6A, f14 = 0x6B, f10 = 0x6D, f12 = 0x6F
    case f15 = 0x71, help = 0x72, home = 0x73, pageUp = 0x74
    case forwardDelete = 0x75, f4 = 0x76, end = 0x77, f2 = 0x78
    case pageDown = 0x79, f1 = 0x7A, leftArrow = 0x7B, rightArrow = 0x7C
    case downArrow = 0x7D, upArrow = 0x7E
}

enum MacMediaKey: Int32, Equatable, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7
    case playPause = 16
    case nextTrack = 17
    case previousTrack = 18
}

enum MouserEngineAction: Equatable, Sendable {
    case cycleDesktops
    case switchScrollMode
    case toggleSmartShift
    case cycleDPI
    case activateActionsRing
}

enum MacActionPlan: Equatable, Sendable {
    case keyboard(keys: [MacVirtualKey], repetitions: Int)
    case mouse(button: UInt32)
    case media(MacMediaKey)
    case engine(MouserEngineAction)
    case noOp
}

struct CustomShortcut: Equatable, Sendable {
    private static let modifierOrder = ["ctrl", "shift", "alt", "super"]
    private static let modifierAliases = [
        "control": "ctrl",
        "option": "alt",
        "cmd": "super",
        "command": "super",
    ]

    let parts: [String]

    init?(modifiers: [String], key: String) {
        let normalizedModifiers = modifiers.map(Self.normalize)
        guard Set(normalizedModifiers).count == normalizedModifiers.count,
              normalizedModifiers.allSatisfy(Self.modifierOrder.contains),
              !Self.modifierOrder.contains(Self.normalize(key))
        else { return nil }
        let normalizedKey = Self.normalize(key)
        let orderedModifiers = Self.modifierOrder.filter(normalizedModifiers.contains)
        let candidate = "custom:" + (orderedModifiers + [normalizedKey]).joined(separator: "+")
        guard MacActionPlanner.plan(for: candidate) != nil else { return nil }
        parts = orderedModifiers + [normalizedKey]
    }

    init?(actionID: String) {
        guard actionID.hasPrefix("custom:") else { return nil }
        let rawParts = actionID.dropFirst(7).split(separator: "+").map(String.init)
        guard let key = rawParts.last else { return nil }
        self.init(modifiers: Array(rawParts.dropLast()), key: key)
    }

    var actionID: String {
        "custom:" + parts.joined(separator: "+")
    }

    var displayText: String {
        parts.map(Self.displayName).joined()
    }

    private static func normalize(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return modifierAliases[lowered] ?? lowered
    }

    private static func displayName(_ name: String) -> String {
        switch name {
        case "ctrl": "⌃"
        case "shift": "⇧"
        case "alt": "⌥"
        case "super": "⌘"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "enter", "return": "↩"
        case "tab": "⇥"
        case "space": "Space"
        case "backspace": "⌫"
        case "delete": "⌦"
        case "escape", "esc": "⎋"
        case "pageup": "Page Up"
        case "pagedown": "Page Down"
        default: name.uppercased()
        }
    }
}

enum MacActionPlanner {
    static func plan(for actionID: String) -> MacActionPlan? {
        if actionID.hasPrefix("custom:") {
            guard let keys = customKeys(in: String(actionID.dropFirst(7))) else { return nil }
            return .keyboard(keys: keys, repetitions: 1)
        }
        guard let action = MouserAction(rawValue: actionID) else { return nil }
        return plan(for: action)
    }

    private static func plan(for action: MouserAction) -> MacActionPlan {
        switch action {
        case .switchWindows: .keyboard(keys: [.command, .tab], repetitions: 1)
        case .switchWindowsReverse: .keyboard(keys: [.command, .shift, .tab], repetitions: 1)
        case .browserBack: .keyboard(keys: [.command, .leftBracket], repetitions: 1)
        case .browserForward: .keyboard(keys: [.command, .rightBracket], repetitions: 1)
        case .copy: .keyboard(keys: [.command, .c], repetitions: 1)
        case .paste: .keyboard(keys: [.command, .v], repetitions: 1)
        case .cut: .keyboard(keys: [.command, .x], repetitions: 1)
        case .undo: .keyboard(keys: [.command, .z], repetitions: 1)
        case .selectAll: .keyboard(keys: [.command, .a], repetitions: 1)
        case .save: .keyboard(keys: [.command, .s], repetitions: 1)
        case .nextTab: .keyboard(keys: [.command, .shift, .rightBracket], repetitions: 1)
        case .previousTab: .keyboard(keys: [.command, .shift, .leftBracket], repetitions: 1)
        case .closeTab: .keyboard(keys: [.command, .w], repetitions: 1)
        case .newTab: .keyboard(keys: [.command, .t], repetitions: 1)
        case .find: .keyboard(keys: [.command, .f], repetitions: 1)
        case .legacyShowDesktop, .legacyTaskView, .missionControl:
            .keyboard(keys: [.control, .upArrow], repetitions: 1)
        case .appExpose: .keyboard(keys: [.control, .downArrow], repetitions: 1)
        case .previousDesktop: .keyboard(keys: [.control, .leftArrow], repetitions: 1)
        case .nextDesktop: .keyboard(keys: [.control, .rightArrow], repetitions: 1)
        case .cycleDesktops: .engine(.cycleDesktops)
        case .showDesktop: .keyboard(keys: [.f11], repetitions: 1)
        case .launchpad: .keyboard(keys: [.f4], repetitions: 1)
        case .volumeUp: .media(.volumeUp)
        case .volumeDown: .media(.volumeDown)
        case .volumeMute: .media(.mute)
        case .playPause: .media(.playPause)
        case .nextTrack: .media(.nextTrack)
        case .previousTrack: .media(.previousTrack)
        case .zoomIn: .keyboard(keys: [.command, .equal], repetitions: 3)
        case .zoomOut: .keyboard(keys: [.command, .minus], repetitions: 3)
        case .pageUp: .keyboard(keys: [.pageUp], repetitions: 1)
        case .pageDown: .keyboard(keys: [.pageDown], repetitions: 1)
        case .home: .keyboard(keys: [.home], repetitions: 1)
        case .end: .keyboard(keys: [.end], repetitions: 1)
        case .switchScrollMode: .engine(.switchScrollMode)
        case .toggleSmartShift: .engine(.toggleSmartShift)
        case .cycleDPI: .engine(.cycleDPI)
        case .activateActionsRing: .engine(.activateActionsRing)
        case .mouseLeft: .mouse(button: 0)
        case .mouseRight: .mouse(button: 1)
        case .mouseMiddle: .mouse(button: 2)
        case .mouseBack: .mouse(button: 3)
        case .mouseForward: .mouse(button: 4)
        case .screenshotRegionClipboard:
            .keyboard(keys: [.command, .shift, .control, .four], repetitions: 1)
        case .screenshotRegionFile:
            .keyboard(keys: [.command, .shift, .four], repetitions: 1)
        case .screenshotFullClipboard:
            .keyboard(keys: [.command, .shift, .control, .three], repetitions: 1)
        case .screenshotFullFile:
            .keyboard(keys: [.command, .shift, .three], repetitions: 1)
        case .passThrough: .noOp
        }
    }

    private static func customKeys(in text: String) -> [MacVirtualKey]? {
        let names = text.lowercased().split(separator: "+").map(String.init)
        guard !names.isEmpty else { return nil }
        var keys: [MacVirtualKey] = []
        for name in names {
            guard let key = customKeyNames[name.trimmingCharacters(in: .whitespaces)] else {
                return nil
            }
            keys.append(key)
        }
        return keys
    }

    static let customKeyNames: [String: MacVirtualKey] = {
        var values: [String: MacVirtualKey] = [
            "ctrl": .control, "control": .control,
            "shift": .shift,
            "alt": .option, "option": .option,
            "super": .command, "cmd": .command, "command": .command,
            "tab": .tab, "space": .space, "enter": .returnKey,
            "return": .returnKey, "esc": .escape, "escape": .escape,
            "backspace": .backspace, "delete": .forwardDelete,
            "left": .leftArrow, "right": .rightArrow,
            "up": .upArrow, "down": .downArrow,
            "pageup": .pageUp, "pagedown": .pageDown,
            "home": .home, "end": .end,
            "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
            "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
            "f1": .f1, "f2": .f2, "f3": .f3, "f4": .f4,
            "f5": .f5, "f6": .f6, "f7": .f7, "f8": .f8,
            "f9": .f9, "f10": .f10, "f11": .f11, "f12": .f12,
        ]
        let letters: [MacVirtualKey] = [
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
            .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
        ]
        for (offset, letter) in letters.enumerated() {
            values[String(UnicodeScalar(97 + offset)!)] = letter
        }
        return values
    }()
}

protocol MouserActionExecuting: Sendable {
    @discardableResult
    func execute(actionID: String) -> Bool
}

struct MacActionExecutor: MouserActionExecuting, Sendable {
    private let engineHandler: @Sendable (MouserEngineAction) -> Bool

    init(engineHandler: @escaping @Sendable (MouserEngineAction) -> Bool = { _ in false }) {
        self.engineHandler = engineHandler
    }

    @discardableResult
    func execute(actionID: String) -> Bool {
        guard let plan = MacActionPlanner.plan(for: actionID) else { return false }
        switch plan {
        case let .keyboard(keys, repetitions):
            for _ in 0..<repetitions { postKeyboard(keys) }
            return true
        case let .mouse(button):
            return postMouse(button)
        case let .media(key):
            return postMedia(key)
        case let .engine(action):
            return engineHandler(action)
        case .noOp:
            return true
        }
    }

    private func postKeyboard(_ keys: [MacVirtualKey]) {
        let flags = keys.reduce(CGEventFlags()) { partial, key in
            partial.union(Self.flag(for: key))
        }
        for key in keys {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
            event.post(tap: .cghidEventTap)
        }
        for key in keys.reversed() {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func postMouse(_ rawButton: UInt32) -> Bool {
        guard let button = CGMouseButton(rawValue: rawButton) else { return false }
        let position = CGEvent(source: nil)?.location ?? .zero
        let down: CGEventType = switch rawButton {
        case 0: .leftMouseDown
        case 1: .rightMouseDown
        default: .otherMouseDown
        }
        let up: CGEventType = switch rawButton {
        case 0: .leftMouseUp
        case 1: .rightMouseUp
        default: .otherMouseUp
        }
        guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: position, mouseButton: button),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: position, mouseButton: button)
        else { return false }
        for event in [downEvent, upEvent] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.injectedEventMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private func postMedia(_ key: MacMediaKey) -> Bool {
        let downData = (key.rawValue << 16) | (0xA << 8)
        let upData = (key.rawValue << 16) | (0xB << 8)
        guard let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(downData),
            data2: -1
        ), let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(upData),
            data2: -1
        ) else { return false }
        down.cgEvent?.post(tap: .cghidEventTap)
        up.cgEvent?.post(tap: .cghidEventTap)
        return true
    }

    private static func flag(for key: MacVirtualKey) -> CGEventFlags {
        switch key {
        case .command: .maskCommand
        case .shift, .rightShift: .maskShift
        case .option, .rightOption: .maskAlternate
        case .control, .rightControl: .maskControl
        default: []
        }
    }

    private static let injectedEventMarker: Int64 = 0x4D4F5554
}
