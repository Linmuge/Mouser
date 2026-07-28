import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

private final class ObserverTokenBox: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh_CN"
    case traditionalChinese = "zh_TW"

    var id: Self { self }

    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .traditionalChinese: Locale(identifier: "zh-Hant")
        }
    }

    func localized(_ key: String, bundle: Bundle = .main) -> String {
        let localization: String
        switch self {
        case .english: localization = "en"
        case .simplifiedChinese: localization = "zh-Hans"
        case .traditionalChinese: localization = "zh-Hant"
        }
        guard let path = bundle.path(forResource: localization, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func formatted(
        _ key: String,
        _ arguments: any CVarArg...,
        bundle: Bundle = .main
    ) -> String {
        formatted(key, arguments: arguments, bundle: bundle)
    }

    func formatted(
        _ key: String,
        arguments: [any CVarArg],
        bundle: Bundle = .main
    ) -> String {
        String(
            format: localized(key, bundle: bundle),
            locale: locale,
            arguments: arguments
        )
    }

    func localizedRuntime(_ source: String, bundle: Bundle = .main) -> String {
        let exact = localized(source, bundle: bundle)
        if exact != source { return exact }

        for template in Self.runtimeTemplates {
            let parts = template.components(separatedBy: "%@")
            guard let values = Self.interpolationValues(in: source, parts: parts) else {
                continue
            }
            return formatted(template, arguments: values.map {
                localizedRuntime($0, bundle: bundle)
            }, bundle: bundle)
        }
        return source
    }

    private static func interpolationValues(in source: String, parts: [String]) -> [String]? {
        guard parts.count >= 2, source.hasPrefix(parts[0]) else { return nil }
        var cursor = source.index(source.startIndex, offsetBy: parts[0].count)
        var values: [String] = []
        for part in parts.dropFirst().dropLast() {
            guard let range = source.range(of: part, range: cursor..<source.endIndex) else {
                return nil
            }
            values.append(String(source[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        guard let suffix = parts.last, source[cursor...].hasSuffix(suffix) else { return nil }
        let valueEnd = source.index(source.endIndex, offsetBy: -suffix.count)
        guard cursor <= valueEnd else { return nil }
        values.append(String(source[cursor..<valueEnd]))
        return values
    }

    private static let runtimeTemplates = [
        "快捷键 %@",
        "%@ · 充电中",
        "电量 %@",
        "当前版本 %@",
        "已是最新版本（%@）",
        "发现新版本 %@",
        "检查失败：%@",
        "检查更新失败（HTTP %@）",
        "导出失败：%@",
        "正在下载并验证 Mouser %@…",
        "安装失败：%@",
        "修改失败：%@",
        "保存失败：%@",
        "同步失败：%@",
        "已连接现有配置 v%@",
        "无法读取现有配置：%@",
        "已识别 · 接收器槽位 %@",
        "已连接 · 接收器槽位 %@",
        "部分设备设置恢复失败（%@）",
        "触觉反馈失败：%@",
        "设备设置失败：%@",
        "已创建 %@ 配置",
        "已保存到 %@",
        "操作环触觉反馈失败：%@",
        "特殊按键监听失败：%@",
        "截图失败（screencapture 退出码 %@）",
        "截图未保存到 %@",
        "不支持的截图动作：%@",
        "更新校验命令失败（%@）",
        "写入临时配置失败（%@）：%@",
        "设置临时配置权限失败（%@）：%@",
        "同步临时配置失败（%@）：%@",
        "配置路径无效：%@",
    ]
}

enum WheelInversionBackend: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case macOS = "off"

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动（优先 HID++）"
        case .macOS: "macOS 事件处理"
        }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case buttons
    case pointerAndScroll
    case haptics
    case actionsRing
    case profiles
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .buttons: "按键"
        case .pointerAndScroll: "指针与滚动"
        case .haptics: "触觉反馈"
        case .actionsRing: "操作环"
        case .profiles: "应用配置"
        case .advanced: "高级"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "macwindow"
        case .buttons: "computermouse"
        case .pointerAndScroll: "cursorarrow.motionlines"
        case .haptics: "waveform.path"
        case .actionsRing: "circle.hexagongrid"
        case .profiles: "square.stack.3d.up"
        case .advanced: "gearshape"
        }
    }
}

enum MouserUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(MouserRelease)
    case failed(String)
}

struct MappedActionInvocation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case press
        case gesture
        case horizontalScroll
    }

    let actionID: String
    let buttonID: String
    let kind: Kind
}

struct HapticTriggerRouter: Sendable {
    var enabled: Bool
    var actionIDs: Set<String>
    var buttonIDs: Set<String>
    var deduplicates: Bool
    private var lastPulseUptime: TimeInterval?

    mutating func waveform(
        for invocation: MappedActionInvocation,
        uptime: TimeInterval
    ) -> Int? {
        guard enabled,
              invocation.kind != .horizontalScroll,
              actionIDs.contains(invocation.actionID) || buttonIDs.contains(invocation.buttonID)
        else { return nil }

        if deduplicates,
           let lastPulseUptime,
           uptime - lastPulseUptime < 0.1 {
            return nil
        }
        lastPulseUptime = uptime
        if invocation.kind == .gesture { return 7 }
        return invocation.actionID == MouserAction.cycleDPI.rawValue ? 3 : 1
    }
}

enum MouseButton: String, CaseIterable, Identifiable, Sendable {
    case middle
    case modeShift
    case back
    case forward
    case gesture
    case actionsRing
    case dpiSwitch

    var id: Self { self }

    var configID: String {
        switch self {
        case .middle: "middle"
        case .modeShift: "mode_shift"
        case .back: "xbutton1"
        case .forward: "xbutton2"
        case .gesture: "gesture"
        case .actionsRing: "actions_ring"
        case .dpiSwitch: "dpi_switch"
        }
    }

    var title: String {
        switch self {
        case .middle: "中键"
        case .modeShift: "模式切换按钮"
        case .back: "后退按钮"
        case .forward: "前进按钮"
        case .gesture: "手势按钮"
        case .actionsRing: "操作环感应区"
        case .dpiSwitch: "DPI 切换按钮"
        }
    }

    var detail: String {
        switch self {
        case .middle: "滚轮按下"
        case .modeShift: "滚轮下方"
        case .back: "拇指区后侧"
        case .forward: "拇指区前侧"
        case .gesture: "拇指托按下"
        case .actionsRing: "MX Master 4 力度感应面板"
        case .dpiSwitch: "MX Vertical 顶部按钮"
        }
    }

    var supportsSlideGesture: Bool {
        self != .dpiSwitch
    }
}

struct ButtonMapping: Identifiable, Equatable, Sendable {
    let button: MouseButton
    var actionID: String

    init(button: MouseButton, action: MouserAction) {
        self.button = button
        actionID = action.rawValue
    }

    init(button: MouseButton, actionID: String) {
        self.button = button
        self.actionID = actionID
    }

    var id: MouseButton { button }

    var action: MouserAction {
        get { MouserAction(rawValue: actionID) ?? .passThrough }
        set { actionID = newValue.rawValue }
    }

    var actionTitle: String {
        if actionID == "gesture_swipe" { return "按住并滑动" }
        if let shortcut = CustomShortcut(actionID: actionID) {
            return "快捷键 \(shortcut.displayText)"
        }
        return MouserAction(rawValue: actionID)?.title ?? actionID
    }
}

enum GestureMappingSlot: String, CaseIterable, Identifiable, Sendable {
    case tap
    case left
    case right
    case up
    case down

    var id: Self { self }

    var title: String {
        switch self {
        case .tap: "轻按"
        case .left: "向左滑动"
        case .right: "向右滑动"
        case .up: "向上滑动"
        case .down: "向下滑动"
        }
    }
}

struct AppProfile: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let bundleID: String?
    let systemImage: String
    var mappings: [ButtonMapping]
    var supplementalMappings: [String: String] = [:]
    var actionsRingSlots: [String] = []
    var appIdentifiers: [String] = []

    func mappingValue(for key: String) -> String? {
        if let button = MouseButton.allCases.first(where: { $0.configID == key }) {
            return mappings.first(where: { $0.button == button })?.actionID
        }
        return supplementalMappings[key]
    }
}

@Observable
@MainActor
final class WorkspaceModel {
    var selectedSection: WorkspaceSection = .overview
    var selectedProfileID: String
    var selectedButton: MouseButton = .back
    var selectedActionsRingIndex = 5

    func localized(_ key: String) -> String {
        language.localized(key)
    }

    func localizedRuntime(_ text: String) -> String {
        language.localizedRuntime(text)
    }

    func formatted(_ key: String, _ arguments: any CVarArg...) -> String {
        language.formatted(key, arguments: arguments)
    }
    private(set) var remappingEnabled = true
    var accessibilityGranted: Bool
    var mouseConnected: Bool
    var batteryLevel: Int
    var batteryCharging: Bool
    private(set) var receiverDetected = false
    private(set) var deviceName = "Logitech 鼠标"
    private(set) var deviceTransport = "—"
    var dpi: Double {
        didSet {
            persistSetting("dpi", value: .integer(Int(dpi)))
            scheduleDPIWrite()
        }
    }
    var dpiPresets: [Int] {
        didSet {
            persistSetting(
                "dpi_presets",
                value: .array(dpiPresets.map(JSONValue.integer))
            )
        }
    }
    var smartShiftEnabled: Bool {
        didSet {
            persistSetting("smart_shift_enabled", value: .bool(smartShiftEnabled))
            scheduleSmartShiftWrite()
        }
    }
    var smartShiftMode: SmartShiftMode {
        didSet {
            persistSetting("smart_shift_mode", value: .string(smartShiftMode.rawValue))
            scheduleSmartShiftWrite()
        }
    }
    var smartShiftThreshold: Double {
        didSet {
            persistSetting("smart_shift_threshold", value: .integer(Int(smartShiftThreshold)))
            scheduleSmartShiftWrite()
        }
    }
    var scrollForce: Double {
        didSet {
            persistSetting("scroll_force", value: .integer(Int(scrollForce)))
            scheduleSmartShiftWrite()
        }
    }
    var invertVerticalScroll: Bool {
        didSet {
            persistSetting("invert_vscroll", value: .bool(invertVerticalScroll))
            updateEventTapSettings()
            scheduleVerticalInversionWrite()
            if !isApplyingSnapshot { synchronizeEventTap() }
        }
    }
    var invertHorizontalScroll: Bool {
        didSet {
            persistSetting("invert_hscroll", value: .bool(invertHorizontalScroll))
            updateEventTapSettings()
            scheduleHorizontalInversionWrite()
            if !isApplyingSnapshot { synchronizeEventTap() }
        }
    }
    var wheelInversionBackend: WheelInversionBackend {
        didSet {
            persistSetting("wheel_divert", value: .string(wheelInversionBackend.rawValue))
            scheduleVerticalInversionWrite()
            scheduleHorizontalInversionWrite()
            if !isApplyingSnapshot { synchronizeEventTap() }
        }
    }
    var ignoreTrackpad: Bool {
        didSet {
            persistSetting("ignore_trackpad", value: .bool(ignoreTrackpad))
            updateEventTapSettings()
        }
    }
    var hapticsEnabled: Bool {
        didSet {
            persistSetting("haptic_enabled", value: .bool(hapticsEnabled))
            synchronizeHapticRouter()
        }
    }
    var hapticStrength: Double {
        didSet {
            persistSetting("haptic_level", value: .integer(Int(hapticStrength)))
            scheduleHapticLevelWrite()
        }
    }
    var hapticActionIDs: [String] {
        didSet {
            persistSetting(
                "action_haptic",
                value: .array(hapticActionIDs.map(JSONValue.string))
            )
            synchronizeHapticRouter()
        }
    }
    var hapticButtonIDs: [String] {
        didSet {
            persistSetting(
                "button_haptic",
                value: .array(hapticButtonIDs.map(JSONValue.string))
            )
            synchronizeHapticRouter()
        }
    }
    var hapticDedup: Bool {
        didSet {
            persistSetting("haptic_dedup", value: .bool(hapticDedup))
            synchronizeHapticRouter()
        }
    }
    var forceSensitivity: Double {
        didSet {
            guard !isApplyingSnapshot, !isApplyingHIDState else { return }
            hasConfiguredForceSensitivity = true
            persistSetting("force_sensitivity", value: .integer(Int(forceSensitivity)))
            scheduleForceSensingWrite()
        }
    }
    private(set) var forceSensingMinimum = 0.0
    private(set) var forceSensingMaximum = 100.0
    private(set) var forceSensingDefault = 50.0
    var appearanceMode: AppearanceMode {
        didSet { persistSetting("appearance_mode", value: .string(appearanceMode.rawValue)) }
    }
    var language: AppLanguage {
        didSet { persistSetting("language", value: .string(language.rawValue)) }
    }
    var debugMode: Bool {
        didSet {
            persistSetting("debug_mode", value: .bool(debugMode))
            appendDebugEvent(debugMode ? "调试事件记录已启用" : "调试事件记录已停用", force: true)
        }
    }
    private(set) var deviceLayoutOverrides: [String: String]
    private var debugEventLog = DiagnosticEventLog(limit: 200)
    private(set) var gestureRecording = false
    private(set) var gestureRecords: [String] = []
    var gestureThreshold: Double {
        didSet {
            persistSetting("gesture_threshold", value: .number(gestureThreshold))
            updateGestureRecognitionSettings()
        }
    }
    var gestureCommitWindowMilliseconds: Double {
        didSet {
            persistSetting(
                "gesture_commit_window_ms",
                value: .integer(Int(gestureCommitWindowMilliseconds))
            )
            updateGestureRecognitionSettings()
        }
    }
    var gestureSettleMilliseconds: Double {
        didSet {
            persistSetting("gesture_settle_ms", value: .integer(Int(gestureSettleMilliseconds)))
            updateGestureRecognitionSettings()
        }
    }
    var gestureCrossRatio: Double {
        didSet {
            persistSetting("gesture_cross_ratio", value: .number(gestureCrossRatio))
            updateGestureRecognitionSettings()
        }
    }
    var horizontalScrollThreshold: Double {
        didSet {
            let clamped = max(0.01, horizontalScrollThreshold)
            if clamped != horizontalScrollThreshold {
                horizontalScrollThreshold = clamped
                return
            }
            persistSetting("hscroll_threshold", value: .number(horizontalScrollThreshold))
            eventTap.updateHorizontalScrollThreshold(horizontalScrollThreshold)
        }
    }
    var actionsRingHoldMilliseconds: Double {
        didSet {
            let value = min(500, max(100, Int(actionsRingHoldMilliseconds)))
            persistSetting("actions_ring_hold_ms", value: .integer(value))
        }
    }
    var actionsRingHoverHaptic: Bool {
        didSet {
            persistSetting(
                "actions_ring_hover_haptic",
                value: .bool(actionsRingHoverHaptic)
            )
        }
    }
    var actionsRingUsesGlobalSlots: Bool {
        didSet {
            persistSetting(
                "actions_ring_use_global",
                value: .bool(actionsRingUsesGlobalSlots)
            )
        }
    }
    var actionsRingGlobalSlots: [String] {
        didSet {
            persistSetting(
                "actions_ring_slots",
                value: .array(actionsRingGlobalSlots.map(JSONValue.string))
            )
        }
    }
    var startMinimized: Bool {
        didSet { persistSetting("start_minimized", value: .bool(startMinimized)) }
    }
    private(set) var startAtLogin: Bool
    private(set) var loginItemStatusText: String
    var automaticallyChecksForUpdates: Bool {
        didSet {
            persistSetting("check_for_updates", value: .bool(automaticallyChecksForUpdates))
            scheduleAutomaticUpdateCheck()
        }
    }
    var screenshotDirectory: String {
        didSet {
            persistSetting("screenshot_directory", value: .string(screenshotDirectory))
        }
    }
    private(set) var screenshotStatusText = "文件截图使用系统默认位置"
    private(set) var updateState: MouserUpdateState = .idle
    private(set) var updateInstallInProgress = false
    private(set) var updateInstallStatusText = ""
    let currentVersion: String
    var profiles: [AppProfile]
    private(set) var configurationLoaded = false
    private(set) var configurationStatus = "正在读取配置…"
    private(set) var nativeEventTapEnabled: Bool
    private(set) var eventTapState: ScrollEventTapState = .stopped
    private(set) var nativeHIDProbeEnabled: Bool
    private(set) var hidppIdentity: HIDPPDeviceIdentity?
    private(set) var hidppControls: [HIDPPReprogrammableControl] = []
    private(set) var hidppStatusText = "未启用"

    var hapticSupported: Bool {
        hidppIdentity?.featureIndexes[.haptic] != nil
    }

    var forceSensingSupported: Bool {
        hidppIdentity?.featureIndexes[.forceSensing] != nil &&
            forceSensingMaximum > forceSensingMinimum
    }

    var availableButtons: [MouseButton] {
        guard let hidppIdentity else { return MouseButton.allCases }
        let supported: Set<MouseButton>
        if !hidppControls.isEmpty {
            let divertableCIDs = Set(hidppControls.filter(\.isDivertable).map(\.cid))
            var discovered: Set<MouseButton> = [.middle, .back, .forward]
            if !divertableCIDs.isDisjoint(with: [0x00C3, 0x00D7]) {
                discovered.insert(.gesture)
            }
            if divertableCIDs.contains(0x00C4) { discovered.insert(.modeShift) }
            if divertableCIDs.contains(0x01A0) { discovered.insert(.actionsRing) }
            if divertableCIDs.contains(0x00FD) { discovered.insert(.dpiSwitch) }
            supported = discovered
        } else {
            let name = hidppIdentity.name.lowercased()
            if name.contains("master 4") {
                supported = [.middle, .back, .forward, .modeShift, .gesture, .actionsRing]
            } else if name.contains("vertical") {
                supported = [.middle, .back, .forward, .dpiSwitch]
            } else if name.contains("master") || name.contains("anywhere") {
                supported = [.middle, .back, .forward, .modeShift, .gesture]
            } else {
                supported = [.middle, .back, .forward]
            }
        }
        return MouseButton.allCases.filter(supported.contains)
    }

    @ObservationIgnored private let configStore: MouserConfigStore?
    @ObservationIgnored private let accessibilityAuthorizer: any AccessibilityAuthorizing
    @ObservationIgnored private let eventTap: any ScrollEventTapping
    @ObservationIgnored private let actionExecutor: any MouserActionExecuting
    @ObservationIgnored private let screenshotCapturer: any ScreenshotCapturing
    @ObservationIgnored private let actionsRingOverlay: any ActionsRingOverlayPresenting
    @ObservationIgnored private let loginItemController: any LoginItemControlling
    @ObservationIgnored private let releaseChecker: any ReleaseChecking
    @ObservationIgnored private let updateInstaller: any NativeUpdatePreparing
    @ObservationIgnored private let deviceDiscovery: any LogitechDeviceDiscovering
    @ObservationIgnored private var isApplyingSnapshot = false
    @ObservationIgnored private var isApplyingHIDState = false
    @ObservationIgnored private var hasConfiguredForceSensitivity = false
    @ObservationIgnored private var pendingWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingHIDWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var recoveryPlanner = SessionRecoveryPlanner()
    @ObservationIgnored private var recoveryTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var deviceActivityRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var awaitingHIDWakeRecovery = false
    @ObservationIgnored private var hidRecoveryInProgress = false
    @ObservationIgnored private var hidProbeTask: Task<Void, Never>?
    @ObservationIgnored private var batteryMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var specialButtonTask: Task<Void, Never>?
    @ObservationIgnored private var actionsRingHoldTask: Task<Void, Never>?
    @ObservationIgnored private var updateCheckTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var hapticRouter = HapticTriggerRouter(
        enabled: true,
        actionIDs: [],
        buttonIDs: [],
        deduplicates: true
    )
    @ObservationIgnored private var actionsRingStateMachine = ActionsRingStateMachine(
        slots: [],
        holdMilliseconds: 250
    )
    @ObservationIgnored private var actionsRingSourceButtonID = MouseButton.actionsRing.configID
    @ObservationIgnored private var lastActionsRingHapticUptime: TimeInterval?
    @ObservationIgnored private var hidppController: (any HIDPPDeviceControlling)?
    @ObservationIgnored private var detectedLogitechDevices: [LogitechHIDDevice] = []
    @ObservationIgnored private var workspaceObservationTokens: [NotificationCenter.ObservationToken] = []
    @ObservationIgnored private var screenUnlockObserver: ObserverTokenBox?

    init(
        selectedProfileID: String,
        accessibilityGranted: Bool,
        mouseConnected: Bool,
        batteryLevel: Int,
        batteryCharging: Bool = false,
        dpi: Double,
        smartShiftEnabled: Bool,
        smartShiftMode: SmartShiftMode = .ratchet,
        smartShiftThreshold: Double,
        scrollForce: Double = 50,
        invertVerticalScroll: Bool,
        invertHorizontalScroll: Bool,
        wheelInversionBackend: WheelInversionBackend = .automatic,
        ignoreTrackpad: Bool,
        hapticsEnabled: Bool,
        hapticStrength: Double,
        hapticActionIDs: [String] = [],
        hapticButtonIDs: [String] = [],
        hapticDedup: Bool = true,
        forceSensitivity: Double = 50,
        appearanceMode: AppearanceMode,
        language: AppLanguage = .english,
        debugMode: Bool = false,
        deviceLayoutOverrides: [String: String] = [:],
        dpiPresets: [Int] = [800, 1200, 1600, 2400],
        startMinimized: Bool = true,
        startAtLogin: Bool = false,
        automaticallyChecksForUpdates: Bool = true,
        screenshotDirectory: String = "",
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "4.0.0",
        gestureThreshold: Double = 50,
        gestureCommitWindowMilliseconds: Double = 400,
        gestureSettleMilliseconds: Double = 90,
        gestureCrossRatio: Double = 0.5,
        horizontalScrollThreshold: Double = 0.1,
        actionsRingHoldMilliseconds: Double = 250,
        actionsRingHoverHaptic: Bool = true,
        actionsRingUsesGlobalSlots: Bool = true,
        actionsRingGlobalSlots: [String] = [
            "mission_control", "play_pause", "show_desktop", "launchpad",
        ],
        profiles: [AppProfile],
        configStore: MouserConfigStore? = nil,
        accessibilityAuthorizer: any AccessibilityAuthorizing = SystemAccessibilityAuthorizer(),
        eventTap: any ScrollEventTapping = CoreGraphicsScrollEventTap(),
        actionExecutor: any MouserActionExecuting = MacActionExecutor(),
        screenshotCapturer: any ScreenshotCapturing = MacScreenshotCaptureService(),
        actionsRingOverlay: any ActionsRingOverlayPresenting = ActionsRingOverlayController(),
        loginItemController: any LoginItemControlling = SystemLoginItemController(),
        releaseChecker: any ReleaseChecking = GitHubReleaseChecker(),
        updateInstaller: any NativeUpdatePreparing = MacNativeUpdateInstaller(),
        deviceDiscovery: any LogitechDeviceDiscovering = CoreHIDLogitechDeviceDiscovery(),
        nativeHIDProbeEnabled: Bool = false,
        nativeEventTapEnabled: Bool = false
    ) {
        self.selectedProfileID = selectedProfileID
        self.accessibilityGranted = accessibilityGranted
        self.mouseConnected = mouseConnected
        self.batteryLevel = batteryLevel
        self.batteryCharging = batteryCharging
        self.dpi = dpi
        self.dpiPresets = dpiPresets.isEmpty ? [800, 1200, 1600, 2400] : dpiPresets
        self.smartShiftEnabled = smartShiftEnabled
        self.smartShiftMode = smartShiftMode
        self.smartShiftThreshold = smartShiftThreshold
        self.scrollForce = scrollForce
        self.invertVerticalScroll = invertVerticalScroll
        self.invertHorizontalScroll = invertHorizontalScroll
        self.wheelInversionBackend = wheelInversionBackend
        self.ignoreTrackpad = ignoreTrackpad
        self.hapticsEnabled = hapticsEnabled
        self.hapticStrength = hapticStrength
        self.hapticActionIDs = hapticActionIDs
        self.hapticButtonIDs = hapticButtonIDs
        self.hapticDedup = hapticDedup
        self.forceSensitivity = forceSensitivity
        self.appearanceMode = appearanceMode
        self.language = language
        self.debugMode = debugMode
        self.deviceLayoutOverrides = deviceLayoutOverrides
        self.startMinimized = startMinimized
        self.startAtLogin = startAtLogin
        loginItemStatusText = startAtLogin ? "已启用" : "未启用"
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.screenshotDirectory = screenshotDirectory
        if !screenshotDirectory.isEmpty {
            screenshotStatusText = screenshotDirectory
        }
        self.currentVersion = currentVersion
        self.gestureThreshold = gestureThreshold
        self.gestureCommitWindowMilliseconds = gestureCommitWindowMilliseconds
        self.gestureSettleMilliseconds = gestureSettleMilliseconds
        self.gestureCrossRatio = gestureCrossRatio
        self.horizontalScrollThreshold = max(0.01, horizontalScrollThreshold)
        self.actionsRingHoldMilliseconds = min(500, max(100, actionsRingHoldMilliseconds))
        self.actionsRingHoverHaptic = actionsRingHoverHaptic
        self.actionsRingUsesGlobalSlots = actionsRingUsesGlobalSlots
        self.actionsRingGlobalSlots = actionsRingGlobalSlots
        self.profiles = profiles
        self.configStore = configStore
        self.accessibilityAuthorizer = accessibilityAuthorizer
        self.eventTap = eventTap
        self.actionExecutor = actionExecutor
        self.screenshotCapturer = screenshotCapturer
        self.actionsRingOverlay = actionsRingOverlay
        self.loginItemController = loginItemController
        self.releaseChecker = releaseChecker
        self.updateInstaller = updateInstaller
        self.deviceDiscovery = deviceDiscovery
        self.nativeHIDProbeEnabled = nativeHIDProbeEnabled
        hidppIdentity = nil
        self.nativeEventTapEnabled = nativeEventTapEnabled
        configurationStatus = configStore == nil ? "预览数据" : "正在读取配置…"
        eventTapState = eventTap.state
        hapticRouter = HapticTriggerRouter(
            enabled: hapticsEnabled,
            actionIDs: Set(hapticActionIDs),
            buttonIDs: Set(hapticButtonIDs),
            deduplicates: hapticDedup
        )
        eventTap.updateDeviceActivityHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDeviceActivityForRecovery()
            }
        }
        configureButtonMappings()
    }

    deinit {
        for task in pendingWrites.values {
            task.cancel()
        }
        for task in pendingHIDWrites.values {
            task.cancel()
        }
        for task in recoveryTasks {
            task.cancel()
        }
        deviceActivityRecoveryTask?.cancel()
        hidProbeTask?.cancel()
        batteryMonitorTask?.cancel()
        specialButtonTask?.cancel()
        actionsRingHoldTask?.cancel()
        updateCheckTask?.cancel()
        screenshotCaptureTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObservationTokens {
            center.removeObserver(token)
        }
        if let screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(screenUnlockObserver.value)
        }
    }

    var selectedProfile: AppProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var actionsRingSlots: [String] {
        if actionsRingUsesGlobalSlots { return actionsRingGlobalSlots }
        guard let slots = selectedProfile?.actionsRingSlots, !slots.isEmpty else {
            return actionsRingGlobalSlots
        }
        return slots
    }

    func setActionsRingSlot(_ actionID: String, at index: Int) {
        guard index >= 0 else { return }
        var slots = actionsRingSlots
        while slots.count <= index {
            slots.append(MouserAction.passThrough.rawValue)
        }
        slots[index] = actionID
        if actionsRingUsesGlobalSlots {
            actionsRingGlobalSlots = slots
            return
        }
        guard let profileIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        profiles[profileIndex].actionsRingSlots = slots
        persist(
            .profileRingSlots(profileID: selectedProfileID, slots: slots),
            key: "mapping.\(selectedProfileID).actions_ring_slots",
            delay: .zero
        )
    }

    static let hapticEligibleActions: [MouserAction] = [
        .switchScrollMode,
        .toggleSmartShift,
        .cycleDPI,
        .volumeMute,
        .playPause,
        .nextTrack,
        .previousTrack,
        .legacyTaskView,
        .switchWindows,
        .switchWindowsReverse,
        .legacyShowDesktop,
    ]

    func setHapticEnabled(_ enabled: Bool, forActionID actionID: String) {
        if enabled {
            guard !hapticActionIDs.contains(actionID) else { return }
            hapticActionIDs.append(actionID)
        } else {
            hapticActionIDs.removeAll { $0 == actionID }
        }
    }

    func setHapticEnabled(_ enabled: Bool, forButtonID buttonID: String) {
        if enabled {
            guard !hapticButtonIDs.contains(buttonID) else { return }
            hapticButtonIDs.append(buttonID)
        } else {
            hapticButtonIDs.removeAll { $0 == buttonID }
        }
    }

    var showsPermissionCallout: Bool {
        !accessibilityGranted
    }

    var deviceStatusText: String {
        if nativeHIDControlConnected { return "原生设备控制已连接" }
        if mouseConnected { return "已检测到，控制未接管" }
        if receiverDetected { return "已检测到接收器，鼠标待确认" }
        return "未检测到 Logitech 设备"
    }

    var batteryText: String {
        (mouseConnected && batteryLevel > 0) ? "\(batteryLevel)%" : "—"
    }

    var batteryStatusText: String {
        guard mouseConnected, batteryLevel > 0 else { return "—" }
        return batteryCharging ? "\(batteryLevel)% · 充电中" : "\(batteryLevel)%"
    }

    private var automaticDeviceProfile: LogitechDeviceProfile {
        LogitechDeviceCatalog.profile(named: hidppIdentity?.name ?? deviceName)
    }

    var deviceLayoutOverrideKey: String {
        deviceLayoutOverrides[automaticDeviceProfile.key] ?? ""
    }

    var deviceProfile: LogitechDeviceProfile {
        LogitechDeviceCatalog.profile(layoutKey: deviceLayoutOverrideKey)
            ?? automaticDeviceProfile
    }

    var dpiRange: ClosedRange<Double> { automaticDeviceProfile.dpiRange }

    func setDeviceLayoutOverride(_ key: String) {
        let validKeys = Set(LogitechDeviceCatalog.manualLayoutChoices.map(\.key))
        guard validKeys.contains(key) else { return }
        let deviceKey = automaticDeviceProfile.key
        if key.isEmpty {
            deviceLayoutOverrides.removeValue(forKey: deviceKey)
        } else {
            deviceLayoutOverrides[deviceKey] = key
        }
        persistSetting(
            "device_layout_overrides",
            value: .object(deviceLayoutOverrides.mapValues(JSONValue.string))
        )
    }

    func setDPIPreset(_ value: Int, at index: Int) {
        guard index >= 0, index < 4 else { return }
        let defaults = [800, 1200, 1600, 2400]
        var presets = dpiPresets
        while presets.count < 4 {
            presets.append(defaults[presets.count])
        }
        presets[index] = min(Int(dpiRange.upperBound), max(Int(dpiRange.lowerBound), value))
        dpiPresets = Array(presets.prefix(4))
    }

    var nativeHIDControlConnected: Bool {
        nativeHIDProbeEnabled && hidppController != nil
    }

    var scrollModeText: String {
        smartShiftEnabled ? "SmartShift" : smartShiftMode.title
    }

    var eventTapStatusText: String {
        guard requiresEventTap else { return "未启用" }
        guard accessibilityGranted else { return "等待辅助功能权限" }
        return switch eventTapState {
        case .stopped: "已停止"
        case .waitingForPermission: "等待辅助功能权限"
        case .running: "正在处理鼠标事件"
        case let .failed(message): message
        }
    }

    var updateStatusText: String {
        switch updateState {
        case .idle: "当前版本 \(currentVersion)"
        case .checking: "正在检查更新…"
        case .upToDate: "已是最新版本（\(currentVersion)）"
        case let .available(release): "发现新版本 \(release.version)"
        case let .failed(message): "检查失败：\(message)"
        }
    }

    var latestReleaseURL: URL? {
        guard case let .available(release) = updateState else { return nil }
        return release.releaseURL
    }

    var debugLogText: String {
        debugEventLog.lines.joined(separator: "\n")
    }

    var gestureRecordsText: String {
        gestureRecords.joined(separator: "\n")
    }

    func clearDebugLog() {
        debugEventLog.clear()
    }

    func setGestureRecording(_ enabled: Bool) {
        gestureRecording = enabled
        appendDebugEvent(enabled ? "手势录制已启用" : "手势录制已停用", force: true)
    }

    func clearGestureRecords() {
        gestureRecords.removeAll(keepingCapacity: true)
    }

    func exportDebugLog() {
        let panel = NSSavePanel()
        panel.title = "导出 Mouser 调试事件"
        panel.nameFieldStringValue = "Mouser-Event-Log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = "\(diagnosticReport)\n\nEvent Log\n\(debugLogText)\n\nGesture Records\n\(gestureRecordsText)\n"
            try Data(content.utf8).write(to: url, options: .atomic)
            configurationStatus = "调试事件已导出"
        } catch {
            configurationStatus = "导出失败：\(error.localizedDescription)"
        }
    }

    var canInstallLatestRelease: Bool {
        guard case let .available(release) = updateState else { return false }
        return release.installAsset != nil && !updateInstallInProgress
    }

    var hasCustomScreenshotDirectory: Bool {
        !screenshotDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var screenshotDirectoryLabel: String {
        hasCustomScreenshotDirectory ? screenshotDirectory : "系统默认位置"
    }

    func setScreenshotDirectory(_ url: URL?) {
        guard let url else { return }
        var isDirectory: ObjCBool = false
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            screenshotStatusText = "请选择有效的文件夹"
            return
        }
        screenshotDirectory = path
        screenshotStatusText = path
    }

    func resetScreenshotDirectory() {
        screenshotDirectory = ""
        screenshotStatusText = "文件截图使用系统默认位置"
    }

    func bootstrap() async {
        refreshAccessibility(prompt: false)
        await loadConfiguration()
        reconcileLoginItemWithConfiguration()
        configureButtonMappings()
        synchronizeEventTap()
        startSessionMonitoring()
        handleForegroundApplication(
            bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        scheduleAutomaticUpdateCheck()
    }

    func checkForUpdates() async {
        updateState = .checking
        do {
            let release = try await releaseChecker.latestRelease()
            updateState = SemanticVersion.isNewer(release.version, than: currentVersion)
                ? .available(release)
                : .upToDate
        } catch is CancellationError {
            updateState = .idle
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openLatestRelease() {
        guard let latestReleaseURL else { return }
        NSWorkspace.shared.open(latestReleaseURL)
    }

    func downloadAndInstallLatestUpdate() async {
        guard case let .available(release) = updateState,
              release.installAsset != nil,
              !updateInstallInProgress
        else { return }
        updateInstallInProgress = true
        updateInstallStatusText = "正在下载并验证 Mouser \(release.version)…"
        defer { updateInstallInProgress = false }
        do {
            let plan = try await updateInstaller.prepare(
                release: release,
                currentAppURL: Bundle.main.bundleURL,
                parentProcessID: ProcessInfo.processInfo.processIdentifier
            )
            updateInstallStatusText = "验证完成，正在安装并重新启动…"
            try MacUpdateInstallHelper.launch(plan)
            NSApp.terminate(nil)
        } catch is CancellationError {
            updateInstallStatusText = "更新已取消"
        } catch {
            updateInstallStatusText = "安装失败：\(error.localizedDescription)"
        }
    }

    var diagnosticReport: String {
        let architecture: String
        #if arch(arm64)
        architecture = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        architecture = "Intel (x86_64)"
        #else
        architecture = "Unknown"
        #endif
        let features = hidppIdentity?.featureIndexes.keys
            .map { String(format: "0x%04X", $0.rawValue) }
            .sorted()
            .joined(separator: ", ") ?? "—"
        return """
        Mouser Diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        Version: \(currentVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Accessibility: \(accessibilityGranted ? "Granted" : "Not granted")
        Device: \(deviceName)
        Transport: \(deviceTransport)
        Mouse connected: \(mouseConnected)
        Receiver detected: \(receiverDetected)
        Battery: \(batteryText)
        Native HID++ enabled: \(nativeHIDProbeEnabled)
        Native HID++ status: \(hidppStatusText)
        HID++ features: \(features)
        Event tap enabled: \(nativeEventTapEnabled)
        Event tap status: \(eventTapStatusText)
        Active profile: \(selectedProfileID)
        Configuration: \(configurationStatus)
        """
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "导出 Mouser 诊断信息"
        panel.nameFieldStringValue = "Mouser-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(diagnosticReport.utf8).write(to: url, options: .atomic)
            configurationStatus = "诊断信息已导出"
        } catch {
            configurationStatus = "导出失败：\(error.localizedDescription)"
        }
    }

    private func scheduleAutomaticUpdateCheck() {
        updateCheckTask?.cancel()
        guard automaticallyChecksForUpdates else { return }
        updateCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                await self.checkForUpdates()
            } catch {
                return
            }
        }
    }

    func setStartAtLogin(_ enabled: Bool) {
        guard enabled != startAtLogin else { return }
        let previous = startAtLogin
        do {
            try loginItemController.setEnabled(enabled)
        } catch {
            loginItemStatusText = "修改失败：\(error.localizedDescription)"
            return
        }

        startAtLogin = enabled
        loginItemStatusText = enabled ? "已启用" : "未启用"
        guard let configStore else { return }
        let taskKey = "setting.start_at_login"
        pendingWrites[taskKey]?.cancel()
        pendingWrites[taskKey] = Task { [weak self] in
            do {
                try await configStore.update(.setting(key: "start_at_login", value: .bool(enabled)))
                guard !Task.isCancelled else { return }
                self?.configurationStatus = "更改已保存"
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.startAtLogin = previous
                do {
                    try self.loginItemController.setEnabled(previous)
                    self.loginItemStatusText = "保存失败：\(error.localizedDescription)"
                } catch {
                    self.loginItemStatusText = "登录项状态不一致，请重新启动 Mouser"
                }
            }
        }
    }

    private func reconcileLoginItemWithConfiguration() {
        guard loginItemController.isEnabled != startAtLogin else {
            loginItemStatusText = startAtLogin ? "已启用" : "未启用"
            return
        }
        do {
            try loginItemController.setEnabled(startAtLogin)
            loginItemStatusText = startAtLogin ? "已启用" : "未启用"
        } catch {
            startAtLogin = loginItemController.isEnabled
            loginItemStatusText = "同步失败：\(error.localizedDescription)"
            persistSetting("start_at_login", value: .bool(startAtLogin))
        }
    }

    func loadConfiguration() async {
        guard let configStore else {
            configurationLoaded = true
            return
        }
        do {
            let snapshot = try await configStore.load()
            apply(snapshot)
            configurationLoaded = true
            configurationStatus = "已连接现有配置 v\(snapshot.version)"
        } catch {
            configurationLoaded = false
            configurationStatus = "无法读取现有配置：\(error.localizedDescription)"
        }
    }

    func monitorAccessibility() async {
        while !Task.isCancelled {
            refreshAccessibility(prompt: false)
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    func monitorLogitechDevices() async {
        for await devices in deviceDiscovery.updates() {
            guard !Task.isCancelled else { return }
            handleDetectedDevicesUpdate(devices)
        }
    }

    func handleDetectedDevicesUpdate(_ devices: [LogitechHIDDevice]) {
        applyDetectedDevices(devices)
        guard nativeHIDProbeEnabled else { return }
        let hasHIDPPInterface = LogitechDeviceInventory.preferredHIDPPInterface(
            from: devices
        ) != nil
        let shouldRestoreSettings = awaitingHIDWakeRecovery ||
            (hasHIDPPInterface && hidppController == nil)
        if shouldRestoreSettings {
            awaitingHIDWakeRecovery = true
            synchronizeEventTap()
        }
        launchHIDProbe(reapplySettings: shouldRestoreSettings)
    }

    func applyDetectedDevices(_ devices: [LogitechHIDDevice]) {
        detectedLogitechDevices = devices
        receiverDetected = devices.contains(where: \.isReceiver)
        if nativeHIDProbeEnabled,
           LogitechDeviceInventory.preferredHIDPPInterface(from: devices) == nil,
           hidppController != nil
        {
            clearHIDPPConnection(status: "等待 HID++ 接口")
        }
        if let hidppIdentity, receiverDetected {
            mouseConnected = true
            deviceName = hidppIdentity.name
            deviceTransport = devices.first(where: \.isReceiver)?.transport ?? deviceTransport
            return
        }
        if let mouse = devices
            .filter(\.isMouse)
            .sorted(by: { lhs, rhs in
                if (lhs.catalogName != nil) != (rhs.catalogName != nil) {
                    return lhs.catalogName != nil
                }
                return lhs.id < rhs.id
            })
            .first
        {
            mouseConnected = true
            deviceName = mouse.displayName
            deviceTransport = mouse.transport
        } else if let receiver = devices.first(where: \.isReceiver) {
            mouseConnected = false
            deviceName = receiver.displayName
            deviceTransport = receiver.transport
        } else {
            mouseConnected = false
            deviceName = "Logitech 鼠标"
            deviceTransport = "—"
        }
    }

    func setNativeHIDProbeEnabled(_ enabled: Bool) {
        guard nativeHIDProbeEnabled != enabled else { return }
        if enabled, nativeEventTapEnabled {
            setNativeEventTapEnabled(false)
        }
        nativeHIDProbeEnabled = enabled
        if configStore != nil {
            UserDefaults.standard.set(enabled, forKey: "nativeHIDProbeEnabled")
        }
        hidProbeTask?.cancel()
        if enabled {
            launchHIDProbe()
        } else {
            clearHIDPPConnection(status: "未启用")
            applyDetectedDevices(detectedLogitechDevices)
        }
        synchronizeEventTap()
    }

    @discardableResult
    func refreshHIDPPIdentity(reapplySettings: Bool = false) async -> Bool {
        guard nativeHIDProbeEnabled else {
            hidppStatusText = "未启用"
            return false
        }
        guard let device = LogitechDeviceInventory.preferredHIDPPInterface(
            from: detectedLogitechDevices
        ) else {
            clearHIDPPConnection(status: "等待 HID++ 接口")
            return false
        }

        hidppStatusText = "正在探测设备…"
        let detectedIdentity = await deviceDiscovery.identify(device)
        guard !Task.isCancelled else { return false }
        guard let identity = detectedIdentity else {
            clearHIDPPConnection(status: "未在接收器中找到兼容鼠标")
            applyDetectedDevices(detectedLogitechDevices)
            return false
        }
        let controller = await deviceDiscovery.controller(for: device, identity: identity)
        guard !Task.isCancelled else { return false }

        specialButtonTask?.cancel()
        specialButtonTask = nil
        hidppIdentity = identity
        hidppController = controller
        mouseConnected = true
        deviceName = identity.name
        deviceTransport = device.transport
        guard let hidppController else {
            batteryMonitorTask?.cancel()
            batteryMonitorTask = nil
            hidppStatusText = identity.deviceIndex == 0xFF
                ? "已识别 · 蓝牙直连"
                : "已识别 · 接收器槽位 \(identity.deviceIndex)"
            return false
        }

        hidppControls = await hidppController.readReprogrammableControls(
            timeout: .milliseconds(500)
        )
        if !availableButtons.contains(selectedButton) {
            selectedButton = availableButtons.first ?? .back
        }

        let settingsRestored: Bool
        if reapplySettings {
            settingsRestored = await restoreHIDPPSettings(
                using: hidppController,
                identity: identity
            )
        } else {
            settingsRestored = true
            let state = await hidppController.readState(timeout: .milliseconds(700))
            applyHIDPPState(state)
            if wheelInversionBackend == .macOS {
                try? await hidppController.setVerticalScrollInverted(
                    false,
                    timeout: .seconds(2)
                )
                try? await hidppController.setHorizontalScrollInverted(
                    false,
                    timeout: .seconds(2)
                )
                synchronizeEventTap()
            }
            hidppStatusText = identity.deviceIndex == 0xFF
                ? "已连接 · 蓝牙直连"
                : "已连接 · 接收器槽位 \(identity.deviceIndex)"
        }
        startBatteryMonitoring(using: hidppController)
        launchSpecialButtonStream()
        return settingsRestored
    }

    private func launchHIDProbe(reapplySettings: Bool = false) {
        hidProbeTask?.cancel()
        hidProbeTask = Task { [weak self] in
            guard let self else { return }
            if reapplySettings {
                if await self.attemptHIDWakeRecovery() {
                    self.finishHIDWakeRecovery()
                }
            } else {
                await self.refreshHIDPPIdentity()
            }
        }
    }

    private func clearHIDPPConnection(status: String) {
        batteryMonitorTask?.cancel()
        batteryMonitorTask = nil
        specialButtonTask?.cancel()
        specialButtonTask = nil
        for task in pendingHIDWrites.values {
            task.cancel()
        }
        pendingHIDWrites.removeAll()
        hidppController = nil
        hidppIdentity = nil
        hidppControls = []
        hidppStatusText = status
    }

    private func startBatteryMonitoring(using controller: any HIDPPDeviceControlling) {
        batteryMonitorTask?.cancel()
        batteryMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                if let battery = await controller.readBatteryState(timeout: .seconds(2)) {
                    guard let self, !Task.isCancelled else { return }
                    batteryLevel = battery.level
                    batteryCharging = battery.charging
                }
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    return
                }
            }
        }
    }

    private func applyHIDPPState(_ state: HIDPPDeviceState) {
        isApplyingHIDState = true
        defer { isApplyingHIDState = false }
        if let dpi = state.dpi {
            self.dpi = Double(dpi)
        }
        if let smartShift = state.smartShift {
            smartShiftMode = smartShift.mode
            smartShiftEnabled = smartShift.automatic
            smartShiftThreshold = Double(smartShift.threshold)
            if smartShift.scrollForce > 0 {
                scrollForce = Double(smartShift.scrollForce)
            }
        }
        if let battery = state.battery {
            batteryLevel = battery.level
            batteryCharging = battery.charging
        }
        if wheelInversionBackend == .automatic,
           let verticalScrollInverted = state.verticalScrollInverted {
            invertVerticalScroll = verticalScrollInverted
        }
        if let force = state.forceSensing {
            forceSensingMinimum = Double(force.minimum)
            forceSensingMaximum = Double(force.maximum)
            forceSensingDefault = Double(force.defaultValue)
            if hasConfiguredForceSensitivity {
                Task { [weak self] in
                    await Task.yield()
                    self?.scheduleForceSensingWrite()
                }
            } else {
                forceSensitivity = Double(force.currentValue)
            }
        }
    }

    private func restoreHIDPPSettings(
        using controller: any HIDPPDeviceControlling,
        identity: HIDPPDeviceIdentity
    ) async -> Bool {
        var failureCount = 0

        if identity.featureIndexes[.adjustableDPI] != nil {
            do {
                try await controller.setDPI(Int(dpi), timeout: .seconds(2))
            } catch {
                failureCount += 1
            }
        }
        if identity.featureIndexes[.smartShiftEnhanced] != nil ||
            identity.featureIndexes[.smartShift] != nil
        {
            do {
                try await controller.setSmartShift(
                    mode: smartShiftMode,
                    automatic: smartShiftEnabled,
                    threshold: Int(smartShiftThreshold),
                    scrollForce: Int(scrollForce),
                    timeout: .seconds(2)
                )
            } catch {
                failureCount += 1
            }
        }
        if identity.featureIndexes[.highResolutionWheelEnhanced] != nil {
            do {
                try await controller.setVerticalScrollInverted(
                    wheelInversionBackend == .automatic && invertVerticalScroll,
                    timeout: .seconds(2)
                )
            } catch {
                failureCount += 1
            }
        }
        if identity.featureIndexes[.thumbWheel] != nil {
            do {
                try await controller.setHorizontalScrollInverted(
                    wheelInversionBackend == .automatic && invertHorizontalScroll,
                    timeout: .seconds(2)
                )
            } catch {
                failureCount += 1
            }
        }
        if identity.featureIndexes[.haptic] != nil, hapticsEnabled {
            do {
                try await controller.setHapticLevel(
                    Int(hapticStrength),
                    timeout: .seconds(2)
                )
            } catch {
                failureCount += 1
            }
        }
        if identity.featureIndexes[.forceSensing] != nil, hasConfiguredForceSensitivity {
            do {
                try await controller.setForceSensing(
                    Int(forceSensitivity),
                    timeout: .seconds(2)
                )
            } catch {
                failureCount += 1
            }
        }

        hidppStatusText = failureCount == 0
            ? "已恢复设备设置"
            : "部分设备设置恢复失败（\(failureCount)）"
        return failureCount == 0
    }

    private func scheduleDPIWrite() {
        let dpi = Int(dpi)
        scheduleHIDWrite(key: "dpi") { controller in
            try await controller.setDPI(dpi, timeout: .seconds(2))
        }
    }

    private func scheduleSmartShiftWrite() {
        let mode = smartShiftMode
        let automatic = smartShiftEnabled
        let threshold = Int(smartShiftThreshold)
        let force = Int(scrollForce)
        scheduleHIDWrite(key: "smart_shift") { controller in
            try await controller.setSmartShift(
                mode: mode,
                automatic: automatic,
                threshold: threshold,
                scrollForce: force,
                timeout: .seconds(2)
            )
        }
    }

    private func scheduleVerticalInversionWrite() {
        let inverted = wheelInversionBackend == .automatic && invertVerticalScroll
        scheduleHIDWrite(key: "invert_vertical") { controller in
            try await controller.setVerticalScrollInverted(
                inverted,
                timeout: .seconds(2)
            )
        }
    }

    private func scheduleHorizontalInversionWrite() {
        let inverted = wheelInversionBackend == .automatic && invertHorizontalScroll
        scheduleHIDWrite(key: "invert_horizontal") { controller in
            try await controller.setHorizontalScrollInverted(
                inverted,
                timeout: .seconds(2)
            )
        }
    }

    private func scheduleHapticLevelWrite() {
        let level = Int(hapticStrength)
        scheduleHIDWrite(key: "haptic_level") { controller in
            try await controller.setHapticLevel(level, timeout: .seconds(2))
        }
    }

    private func scheduleForceSensingWrite() {
        let value = Int(forceSensitivity)
        scheduleHIDWrite(key: "force_sensing") { controller in
            try await controller.setForceSensing(value, timeout: .seconds(2))
        }
    }

    func playHapticPreview() async {
        guard hapticsEnabled, hapticSupported, let hidppController else { return }
        do {
            try await hidppController.playHapticWaveform(0, timeout: .seconds(2))
            hidppStatusText = "触觉反馈已播放"
        } catch {
            hidppStatusText = "触觉反馈失败：\(error.localizedDescription)"
        }
    }

    private func scheduleHIDWrite(
        key: String,
        delay: Duration = .milliseconds(180),
        operation: @escaping @Sendable (any HIDPPDeviceControlling) async throws -> Void
    ) {
        guard !isApplyingSnapshot,
              !isApplyingHIDState,
              nativeHIDProbeEnabled,
              let hidppController
        else { return }

        pendingHIDWrites[key]?.cancel()
        pendingHIDWrites[key] = Task { [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                try await operation(hidppController)
                guard !Task.isCancelled else { return }
                self?.hidppStatusText = "设备设置已应用"
            } catch is CancellationError {
                return
            } catch {
                self?.hidppStatusText = "设备设置失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshAccessibility(
        using authorizer: (any AccessibilityAuthorizing)? = nil,
        prompt: Bool
    ) {
        accessibilityGranted = (authorizer ?? accessibilityAuthorizer).isTrusted(prompt: prompt)
        synchronizeEventTap()
    }

    func requestAccessibility() {
        refreshAccessibility(prompt: true)
    }

    func setNativeEventTapEnabled(_ enabled: Bool) {
        guard nativeEventTapEnabled != enabled else { return }
        if enabled, nativeHIDProbeEnabled {
            setNativeHIDProbeEnabled(false)
        }
        nativeEventTapEnabled = enabled
        if configStore != nil {
            UserDefaults.standard.set(enabled, forKey: "nativeEventTapEnabled")
        }
        synchronizeEventTap()
    }

    func setRemappingEnabled(_ enabled: Bool) {
        guard remappingEnabled != enabled else { return }
        remappingEnabled = enabled
        if enabled {
            launchSpecialButtonStream()
        } else {
            specialButtonTask?.cancel()
            specialButtonTask = nil
            resetActionsRing()
        }
        synchronizeEventTap()
        appendDebugEvent(enabled ? "按键映射已启用" : "按键映射已暂停", force: true)
    }

    private func startSessionMonitoring() {
        guard workspaceObservationTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter
        workspaceObservationTokens.append(center.addObserver(
            of: workspace,
            for: .didWake,
            using: { [weak self] _ in
                self?.handleSessionRecoverySignal(.wake)
            }
        ))
        workspaceObservationTokens.append(center.addObserver(
            of: workspace,
            for: .sessionDidBecomeActive,
            using: { [weak self] _ in
                self?.handleSessionRecoverySignal(.sessionActivated)
            }
        ))
        workspaceObservationTokens.append(center.addObserver(
            of: workspace,
            for: .didActivateApplication,
            using: { [weak self] message in
                self?.handleForegroundApplication(
                    bundleIdentifier: message.application.bundleIdentifier
                )
            }
        ))
        screenUnlockObserver = ObserverTokenBox(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleSessionRecoverySignal(.screenUnlock)
                    }
                }
            )
        )
    }

    func monitorConsoleLock(
        reader: IOConsoleLockStateReader = IOConsoleLockStateReader()
    ) async {
        var detector = ConsoleLockTransitionDetector()
        while !Task.isCancelled {
            if detector.observe(reader.read()) {
                handleSessionRecoverySignal(.screenUnlock)
            }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
        }
    }

    func selectProfile(id: String) {
        guard profiles.contains(where: { $0.id == id }), selectedProfileID != id else { return }
        selectedProfileID = id
        configureButtonMappings()
        synchronizeEventTap()
        launchSpecialButtonStream()
        persist(.activeProfile(id: id), key: "active_profile", delay: .zero)
    }

    @discardableResult
    func addApplicationProfile(_ candidate: ApplicationProfileCandidate) -> Bool {
        let candidateIdentities = Set(candidate.appIdentifiers.map { $0.lowercased() })
        guard !candidateIdentities.isEmpty,
              !profiles.contains(where: { profile in
                  !candidateIdentities.isDisjoint(
                    with: Set(profile.appIdentifiers.map { $0.lowercased() })
                  )
              })
        else {
            configurationStatus = "这个应用已有配置"
            return false
        }

        let defaultProfile = profiles.first(where: { $0.id == "default" })
        let id = uniqueProfileID(for: candidate.bundleIdentifier ?? candidate.name)
        let profile = AppProfile(
            id: id,
            name: candidate.name,
            bundleID: candidate.bundleIdentifier ?? candidate.appIdentifiers.first,
            systemImage: candidate.systemImage,
            mappings: defaultProfile?.mappings ?? MouseButton.allCases.map {
                ButtonMapping(button: $0, action: .passThrough)
            },
            supplementalMappings: defaultProfile?.supplementalMappings ?? [:],
            actionsRingSlots: defaultProfile?.actionsRingSlots ?? [],
            appIdentifiers: candidate.appIdentifiers
        )
        profiles.append(profile)
        profiles.sort { lhs, rhs in
            if lhs.id == "default" { return true }
            if rhs.id == "default" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        selectedProfileID = id
        configureButtonMappings()
        synchronizeEventTap()
        launchSpecialButtonStream()
        persist(
            .createProfile(
                id: id,
                label: candidate.name,
                appIdentifiers: candidate.appIdentifiers,
                copyFrom: "default"
            ),
            key: "profile.create.\(id)",
            delay: .zero
        )
        configurationStatus = "已创建 \(candidate.name) 配置"
        return true
    }

    @discardableResult
    func deleteProfile(id: String) -> Bool {
        guard id != "default", profiles.contains(where: { $0.id == id }) else {
            return false
        }
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id {
            selectedProfileID = profiles.first(where: { $0.id == "default" })?.id
                ?? profiles.first?.id
                ?? "default"
        }
        configureButtonMappings()
        synchronizeEventTap()
        launchSpecialButtonStream()
        persist(.deleteProfile(id: id), key: "profile.delete.\(id)", delay: .zero)
        configurationStatus = "配置已删除"
        return true
    }

    private func uniqueProfileID(for source: String) -> String {
        let base = String(
            source.lowercased().unicodeScalars.map { scalar -> Character in
                let value = scalar.value
                let isLetter = (97...122).contains(value)
                let isDigit = (48...57).contains(value)
                return (isLetter || isDigit) ? Character(String(scalar)) : "_"
            }
        )
        .split(separator: "_")
        .filter { !$0.isEmpty }
        .joined(separator: "_")
        .prefix(32)
        let stem = base.isEmpty ? "application" : String(base)
        var candidate = stem
        var suffix = 2
        while profiles.contains(where: { $0.id == candidate }) {
            candidate = "\(stem.prefix(27))_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func handleForegroundApplication(bundleIdentifier: String?) {
        guard let normalized = bundleIdentifier?.lowercased(), !normalized.isEmpty else { return }
        let target = profiles.first { profile in
            guard profile.id != "default" else { return false }
            let identifiers = profile.appIdentifiers.isEmpty
                ? [profile.bundleID].compactMap { $0 }
                : profile.appIdentifiers
            return identifiers.contains { $0.lowercased() == normalized }
        } ?? profiles.first(where: { $0.id == "default" })
        guard let target, selectedProfileID != target.id else { return }
        selectedProfileID = target.id
        configureButtonMappings()
        synchronizeEventTap()
        launchSpecialButtonStream()
    }

    func mapping(for button: MouseButton) -> ButtonMapping? {
        selectedProfile?.mappings.first { $0.button == button }
    }

    func setAction(_ action: MouserAction, for button: MouseButton) {
        setActionID(action.rawValue, for: button)
    }

    func setActionID(_ actionID: String, for button: MouseButton) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }),
              let mappingIndex = profiles[profileIndex].mappings.firstIndex(where: { $0.button == button })
        else { return }
        profiles[profileIndex].mappings[mappingIndex].actionID = actionID
        configureButtonMappings()
        synchronizeEventTap()
        launchSpecialButtonStream()
        persist(
            .mapping(profileID: selectedProfileID, buttonID: button.configID, actionID: actionID),
            key: "mapping.\(selectedProfileID).\(button.configID)",
            delay: .zero
        )
    }

    func gestureActionID(for button: MouseButton, slot: GestureMappingSlot) -> String {
        selectedProfile?.mappingValue(for: "\(button.configID)_\(slot.rawValue)")
            ?? MouserAction.passThrough.rawValue
    }

    func supplementalActionID(for key: String) -> String {
        selectedProfile?.supplementalMappings[key] ?? MouserAction.passThrough.rawValue
    }

    func setSupplementalActionID(_ actionID: String, for key: String) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        profiles[profileIndex].supplementalMappings[key] = actionID
        configureButtonMappings()
        synchronizeEventTap()
        persist(
            .mapping(
                profileID: selectedProfileID,
                buttonID: key,
                actionID: actionID
            ),
            key: "mapping.\(selectedProfileID).\(key)",
            delay: .zero
        )
    }

    func setGestureAction(
        _ action: MouserAction,
        for button: MouseButton,
        slot: GestureMappingSlot
    ) {
        setGestureActionID(action.rawValue, for: button, slot: slot)
    }

    func setGestureActionID(
        _ actionID: String,
        for button: MouseButton,
        slot: GestureMappingSlot
    ) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        let mappingKey = "\(button.configID)_\(slot.rawValue)"
        profiles[profileIndex].supplementalMappings[mappingKey] = actionID
        configureButtonMappings()
        persist(
            .mapping(
                profileID: selectedProfileID,
                buttonID: mappingKey,
                actionID: actionID
            ),
            key: "mapping.\(selectedProfileID).\(mappingKey)",
            delay: .zero
        )
    }

    func flushPendingWrites() async {
        let tasks = Array(pendingWrites.values)
        for task in tasks {
            await task.value
        }
    }

    func flushPendingHIDWrites() async {
        let tasks = Array(pendingHIDWrites.values)
        for task in tasks {
            await task.value
        }
    }

    private func apply(_ snapshot: MouserConfigurationSnapshot) {
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }
        profiles = snapshot.profiles
        selectedProfileID = profiles.contains(where: { $0.id == snapshot.activeProfileID })
            ? snapshot.activeProfileID
            : profiles.first?.id ?? "default"
        dpi = Double(snapshot.dpi)
        dpiPresets = snapshot.dpiPresets
        smartShiftEnabled = snapshot.smartShiftEnabled
        smartShiftMode = snapshot.smartShiftMode
        smartShiftThreshold = Double(snapshot.smartShiftThreshold)
        scrollForce = Double(snapshot.scrollForce)
        invertVerticalScroll = snapshot.invertVerticalScroll
        invertHorizontalScroll = snapshot.invertHorizontalScroll
        wheelInversionBackend = snapshot.wheelInversionBackend
        ignoreTrackpad = snapshot.ignoreTrackpad
        hapticsEnabled = snapshot.hapticsEnabled
        hapticStrength = Double(snapshot.hapticLevel)
        hapticActionIDs = snapshot.hapticActionIDs
        hapticButtonIDs = snapshot.hapticButtonIDs
        hapticDedup = snapshot.hapticDedup
        hasConfiguredForceSensitivity = snapshot.forceSensitivity != nil
        if let forceSensitivity = snapshot.forceSensitivity {
            self.forceSensitivity = Double(forceSensitivity)
        }
        appearanceMode = snapshot.appearanceMode
        language = snapshot.language
        debugMode = snapshot.debugMode
        deviceLayoutOverrides = snapshot.deviceLayoutOverrides
        startMinimized = snapshot.startMinimized
        startAtLogin = snapshot.startAtLogin
        loginItemStatusText = startAtLogin ? "已启用" : "未启用"
        automaticallyChecksForUpdates = snapshot.checkForUpdates
        screenshotDirectory = snapshot.screenshotDirectory
        screenshotStatusText = snapshot.screenshotDirectory.isEmpty
            ? "文件截图使用系统默认位置"
            : snapshot.screenshotDirectory
        gestureThreshold = snapshot.gestureThreshold
        gestureCommitWindowMilliseconds = snapshot.gestureCommitWindowMilliseconds
        gestureSettleMilliseconds = snapshot.gestureSettleMilliseconds
        gestureCrossRatio = snapshot.gestureCrossRatio
        horizontalScrollThreshold = snapshot.horizontalScrollThreshold
        actionsRingHoldMilliseconds = Double(snapshot.actionsRingHoldMilliseconds)
        actionsRingHoverHaptic = snapshot.actionsRingHoverHaptic
        actionsRingUsesGlobalSlots = snapshot.actionsRingUsesGlobalSlots
        actionsRingGlobalSlots = snapshot.actionsRingGlobalSlots
        configureButtonMappings()
        updateEventTapSettings()
    }

    private func updateEventTapSettings() {
        eventTap.updateSettings(
            ScrollInversionSettings(
                invertVertical: usesMacOSWheelInversion && invertVerticalScroll,
                invertHorizontal: usesMacOSWheelInversion && invertHorizontalScroll,
                ignoreTrackpad: ignoreTrackpad
            )
        )
    }

    private var usesMacOSWheelInversion: Bool {
        nativeEventTapEnabled ||
            (nativeHIDProbeEnabled && wheelInversionBackend == .macOS)
    }

    private var requiresEventTap: Bool {
        if awaitingHIDWakeRecovery && nativeHIDProbeEnabled {
            return true
        }
        return remappingEnabled && (
            hasActiveOSButtonMappings ||
                (usesMacOSWheelInversion && (invertVerticalScroll || invertHorizontalScroll))
        )
    }

    private func configureButtonMappings() {
        resetActionsRing()
        updateGestureRecognitionSettings()
        eventTap.updateHorizontalScrollThreshold(horizontalScrollThreshold)
        let mappings = Dictionary(uniqueKeysWithValues: (selectedProfile?.mappings ?? []).map {
            ($0.button, $0.actionID)
        })
        eventTap.updateButtonMappings(
            mappings,
            gestureMappings: selectedProfile?.supplementalMappings ?? [:]
        ) { [weak self] invocation in
            Task { @MainActor [weak self] in
                self?.executeMappedAction(invocation)
            }
        }
    }

    private func updateGestureRecognitionSettings() {
        eventTap.updateGestureSettings(
            GestureRecognitionSettings(
                threshold: gestureThreshold,
                commitWindowMilliseconds: gestureCommitWindowMilliseconds,
                settleMilliseconds: gestureSettleMilliseconds,
                crossRatio: gestureCrossRatio
            )
        )
    }

    private var hasActiveOSButtonMappings: Bool {
        let osButtons: Set<MouseButton> = [.middle, .back, .forward]
        let hasPhysicalMapping = selectedProfile?.mappings.contains {
            osButtons.contains($0.button) && $0.actionID != MouserAction.passThrough.rawValue
        } ?? false
        let hasHorizontalScrollMapping = ["hscroll_left", "hscroll_right"].contains { key in
            selectedProfile?.supplementalMappings[key].map {
                $0 != MouserAction.passThrough.rawValue
            } ?? false
        }
        let hasExternallyArmedGesture = selectedProfile?.mappingValue(
            for: MouseButton.modeShift.configID
        ) == "gesture_swipe"
        return hasPhysicalMapping || hasHorizontalScrollMapping || hasExternallyArmedGesture
    }

    private func executeMappedAction(
        _ invocation: MappedActionInvocation,
        playMappedHaptic: Bool = true
    ) {
        let actionID = invocation.actionID
        appendDebugEvent(
            "action=\(actionID) button=\(invocation.buttonID) kind=\(invocation.kind)"
        )
        if playMappedHaptic {
            playMappedHapticIfNeeded(for: invocation)
        }
        guard let action = MouserAction(rawValue: actionID) else {
            _ = actionExecutor.execute(actionID: actionID)
            return
        }
        if hasCustomScreenshotDirectory,
           action == .screenshotRegionFile || action == .screenshotFullFile {
            captureScreenshotFile(action)
            return
        }
        switch action {
        case .switchScrollMode:
            smartShiftEnabled = false
            smartShiftMode = smartShiftMode == .ratchet ? .freeSpin : .ratchet
        case .toggleSmartShift:
            smartShiftEnabled.toggle()
        case .cycleDPI:
            let current = Int(dpi)
            let presets = dpiPresets.isEmpty ? [800, 1200, 1600, 2400] : dpiPresets
            let next: Int
            if let index = presets.firstIndex(of: current) {
                next = presets[(index + 1) % presets.count]
            } else {
                next = presets[0]
            }
            dpi = Double(next)
        case .cycleDesktops:
            _ = actionExecutor.execute(actionID: MouserAction.nextDesktop.rawValue)
        case .activateActionsRing:
            toggleActionsRing(sourceButtonID: invocation.buttonID)
        default:
            _ = actionExecutor.execute(actionID: actionID)
        }
    }

    private func captureScreenshotFile(_ action: MouserAction) {
        let directoryURL = URL(
            filePath: screenshotDirectory,
            directoryHint: .isDirectory
        )
        screenshotCaptureTask?.cancel()
        screenshotStatusText = "正在截图…"
        screenshotCaptureTask = Task { [weak self, screenshotCapturer] in
            do {
                let targetURL = try await screenshotCapturer.capture(
                    action,
                    directoryURL: directoryURL
                )
                guard !Task.isCancelled else { return }
                self?.screenshotStatusText = "已保存到 \(targetURL.path(percentEncoded: false))"
            } catch is CancellationError {
                return
            } catch {
                self?.screenshotStatusText = error.localizedDescription
            }
        }
    }

    private func synchronizeHapticRouter() {
        hapticRouter.enabled = hapticsEnabled
        hapticRouter.actionIDs = Set(hapticActionIDs)
        hapticRouter.buttonIDs = Set(hapticButtonIDs)
        hapticRouter.deduplicates = hapticDedup
    }

    private func playMappedHapticIfNeeded(for invocation: MappedActionInvocation) {
        guard let waveform = hapticRouter.waveform(
            for: invocation,
            uptime: ProcessInfo.processInfo.systemUptime
        ), let hidppController, hapticSupported
        else { return }
        Task { [weak self] in
            do {
                try await hidppController.playHapticWaveform(
                    waveform,
                    timeout: .seconds(2)
                )
            } catch {
                self?.hidppStatusText = "触觉反馈失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggleActionsRing(sourceButtonID: String) {
        actionsRingSourceButtonID = sourceButtonID
        refreshActionsRingStateMachineConfiguration()
        applyActionsRingEffects(actionsRingStateMachine.toggle())
    }

    private func beginActionsRingPress(sourceButtonID: String) {
        actionsRingSourceButtonID = sourceButtonID
        refreshActionsRingStateMachineConfiguration()
        let effects = actionsRingStateMachine.buttonDown()
        applyActionsRingEffects(effects)
        actionsRingHoldTask?.cancel()
        guard actionsRingStateMachine.state == .waiting else { return }
        let hold = Int(actionsRingHoldMilliseconds)
        actionsRingHoldTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(hold))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyActionsRingEffects(self?.actionsRingStateMachine.holdElapsed() ?? [])
        }
    }

    private func endActionsRingPress() {
        actionsRingHoldTask?.cancel()
        actionsRingHoldTask = nil
        applyActionsRingEffects(actionsRingStateMachine.buttonUp())
    }

    private func moveActionsRing(dx: Int16, dy: Int16) {
        applyActionsRingEffects(actionsRingStateMachine.move(dx: dx, dy: dy))
    }

    private func selectActionsRingSector(_ index: Int) {
        applyActionsRingEffects(actionsRingStateMachine.selectToggleSector(index))
    }

    private func dismissActionsRing() {
        applyActionsRingEffects(actionsRingStateMachine.dismiss())
    }

    private func refreshActionsRingStateMachineConfiguration() {
        actionsRingStateMachine.slots = actionsRingSlots
        actionsRingStateMachine.holdMilliseconds = Int(actionsRingHoldMilliseconds)
    }

    private func resetActionsRing() {
        actionsRingHoldTask?.cancel()
        actionsRingHoldTask = nil
        actionsRingStateMachine = ActionsRingStateMachine(
            slots: actionsRingSlots,
            holdMilliseconds: Int(actionsRingHoldMilliseconds)
        )
        actionsRingOverlay.hide()
    }

    private func applyActionsRingEffects(_ effects: [ActionsRingEffect]) {
        for effect in effects {
            switch effect {
            case let .show(interactive):
                actionsRingOverlay.show(
                    slots: actionsRingStateMachine.slots,
                    highlightedIndex: actionsRingStateMachine.selectedSector,
                    interactive: interactive,
                    language: language,
                    at: NSEvent.mouseLocation,
                    onSelect: { [weak self] index in self?.selectActionsRingSector(index) },
                    onDismiss: { [weak self] in self?.dismissActionsRing() }
                )
            case .hide:
                actionsRingOverlay.hide()
            case let .highlight(index):
                actionsRingOverlay.updateHighlight(index)
                if index != nil, actionsRingHoverHaptic {
                    playActionsRingHaptic(waveform: 0, requiresButtonAllowlist: false)
                }
            case let .execute(actionID):
                guard actionID != MouserAction.passThrough.rawValue,
                      actionID != MouserAction.activateActionsRing.rawValue
                else { continue }
                executeMappedAction(
                    MappedActionInvocation(
                        actionID: actionID,
                        buttonID: actionsRingSourceButtonID,
                        kind: .gesture
                    ),
                    playMappedHaptic: false
                )
            case let .haptic(waveform):
                playActionsRingHaptic(waveform: waveform, requiresButtonAllowlist: true)
            }
        }
    }

    private func playActionsRingHaptic(waveform: Int, requiresButtonAllowlist: Bool) {
        guard hapticsEnabled, hapticSupported, let hidppController else { return }
        if requiresButtonAllowlist, !hapticButtonIDs.contains(actionsRingSourceButtonID) { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if hapticDedup,
           let lastActionsRingHapticUptime,
           uptime - lastActionsRingHapticUptime < 0.1 {
            return
        }
        lastActionsRingHapticUptime = uptime
        Task { [weak self] in
            do {
                try await hidppController.playHapticWaveform(waveform, timeout: .seconds(2))
            } catch {
                self?.hidppStatusText = "操作环触觉反馈失败：\(error.localizedDescription)"
            }
        }
    }

    private func launchSpecialButtonStream() {
        specialButtonTask?.cancel()
        specialButtonTask = nil
        guard remappingEnabled, nativeHIDProbeEnabled, let hidppController else { return }
        let specialButtons = Set(availableButtons).intersection([
            .modeShift, .gesture, .actionsRing, .dpiSwitch,
        ])
        let mappedButtons = Set((selectedProfile?.mappings ?? []).compactMap { mapping in
            specialButtons.contains(mapping.button) &&
                mapping.actionID != MouserAction.passThrough.rawValue
                ? mapping.button
                : nil
        })
        guard !mappedButtons.isEmpty else { return }
        let ringButtons = Set(mappedButtons.filter { button in
            self.selectedProfile?.mappingValue(for: button.configID) ==
                MouserAction.activateActionsRing.rawValue
        })
        let nativeGestureButtons = Set(mappedButtons.filter { button in
            (button == .gesture || button == .actionsRing) &&
                self.selectedProfile?.mappingValue(for: button.configID) == "gesture_swipe"
        })
        let externalGestureButtons = Set(mappedButtons.filter { button in
            button == .modeShift &&
                self.selectedProfile?.mappingValue(for: button.configID) == "gesture_swipe"
        })
        var rawXYButtons = nativeGestureButtons
        rawXYButtons.formUnion(ringButtons)
        let recognizerSettings = GestureRecognitionSettings(
            threshold: gestureThreshold,
            commitWindowMilliseconds: gestureCommitWindowMilliseconds,
            settleMilliseconds: gestureSettleMilliseconds,
            crossRatio: gestureCrossRatio
        )

        specialButtonTask = Task { [weak self] in
            var gestureRecognizer = GestureRecognizer(
                threshold: recognizerSettings.threshold,
                commitWindowMilliseconds: recognizerSettings.commitWindowMilliseconds,
                settleMilliseconds: recognizerSettings.settleMilliseconds,
                crossRatio: recognizerSettings.crossRatio
            )
            var activeNativeGestureButton: MouseButton?
            do {
                let events = try await hidppController.specialInputEvents(
                    for: mappedButtons,
                    rawXYButtons: rawXYButtons,
                    timeout: .seconds(2)
                )
                for try await input in events {
                    guard !Task.isCancelled else { return }
                    switch input {
                    case let .button(event):
                        self?.recordGestureEvent(
                            "button=\(event.button.configID) \(event.isPressed ? "down" : "up")"
                        )
                        if ringButtons.contains(event.button) {
                            if event.isPressed {
                                self?.beginActionsRingPress(sourceButtonID: event.button.configID)
                            } else {
                                self?.endActionsRingPress()
                            }
                            continue
                        }
                        if nativeGestureButtons.contains(event.button) {
                            if event.isPressed {
                                activeNativeGestureButton = event.button
                                gestureRecognizer.begin()
                            } else if activeNativeGestureButton == event.button {
                                activeNativeGestureButton = nil
                                if gestureRecognizer.end(),
                                   let actionID = self?.selectedProfile?.mappingValue(
                                    for: "\(event.button.configID)_tap"
                                   ),
                                   actionID != MouserAction.passThrough.rawValue
                                {
                                    self?.executeMappedAction(
                                        MappedActionInvocation(
                                            actionID: actionID,
                                            buttonID: event.button.configID,
                                            kind: .gesture
                                        )
                                    )
                                }
                            }
                            continue
                        }
                        if externalGestureButtons.contains(event.button) {
                            if event.isPressed {
                                self?.eventTap.beginExternalGesture(for: event.button)
                            } else {
                                self?.eventTap.endExternalGesture(for: event.button)
                            }
                            continue
                        }
                        guard event.isPressed,
                              let actionID = self?.selectedProfile?.mappings.first(
                                where: { $0.button == event.button }
                              )?.actionID
                        else { continue }
                        self?.executeMappedAction(
                            MappedActionInvocation(
                                actionID: actionID,
                                buttonID: event.button.configID,
                                kind: .press
                            )
                        )
                    case let .movement(dx, dy):
                        self?.recordGestureEvent("move dx=\(dx) dy=\(dy)")
                        if self?.actionsRingStateMachine.state == .showingHeld {
                            self?.moveActionsRing(dx: dx, dy: dy)
                            continue
                        }
                        guard let activeNativeGestureButton else { continue }
                        let directions = gestureRecognizer.sample(
                            dx: Double(dx),
                            dy: Double(dy),
                            source: .hidRawXY,
                            at: ProcessInfo.processInfo.systemUptime
                        )
                        for direction in directions {
                            guard let actionID = self?.selectedProfile?.mappingValue(
                                for: "\(activeNativeGestureButton.configID)_\(direction.rawValue)"
                            ), actionID != MouserAction.passThrough.rawValue else { continue }
                            self?.executeMappedAction(
                                MappedActionInvocation(
                                    actionID: actionID,
                                    buttonID: activeNativeGestureButton.configID,
                                    kind: .gesture
                                )
                            )
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.hidppStatusText = "特殊按键监听失败：\(error.localizedDescription)"
            }
        }
    }

    private func synchronizeEventTap() {
        updateEventTapSettings()
        if accessibilityGranted, requiresEventTap {
            _ = eventTap.start()
        } else if eventTap.state != .stopped {
            eventTap.stop()
        }
        eventTapState = eventTap.state
    }

    private func appendDebugEvent(_ message: String, force: Bool = false) {
        guard debugMode || force else { return }
        debugEventLog.append(message)
    }

    private func recordGestureEvent(_ message: String) {
        guard gestureRecording else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        gestureRecords.append("[\(formatter.string(from: Date()))] \(message)")
        if gestureRecords.count > 80 {
            gestureRecords.removeFirst(gestureRecords.count - 80)
        }
        appendDebugEvent("gesture \(message)")
    }

    func handleSessionRecoverySignal(_ signal: SessionRecoverySignal) {
        guard (requiresEventTap && accessibilityGranted) ||
                nativeHIDProbeEnabled
        else { return }
        if nativeHIDProbeEnabled {
            awaitingHIDWakeRecovery = true
            synchronizeEventTap()
        }
        let uptime = Duration.seconds(ProcessInfo.processInfo.systemUptime)
        let delays = recoveryPlanner.schedule(for: signal, uptime: uptime)
        guard !delays.isEmpty else { return }

        for task in recoveryTasks {
            task.cancel()
        }
        recoveryTasks = delays.map { [weak self] delay in
            Task {
                do {
                    if delay > .zero {
                        try await Task.sleep(for: delay)
                    }
                    guard let self, !Task.isCancelled else { return }
                    if self.requiresEventTap,
                       self.accessibilityGranted {
                        _ = self.eventTap.rebuild()
                        self.eventTapState = self.eventTap.state
                    }
                    if self.nativeHIDProbeEnabled,
                       self.awaitingHIDWakeRecovery,
                       await self.attemptHIDWakeRecovery()
                    {
                        self.finishHIDWakeRecovery()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private func handleDeviceActivityForRecovery() {
        guard nativeHIDProbeEnabled,
              awaitingHIDWakeRecovery,
              !hidRecoveryInProgress,
              deviceActivityRecoveryTask == nil
        else { return }
        let uptime = Duration.seconds(ProcessInfo.processInfo.systemUptime)
        guard !recoveryPlanner.schedule(
            for: .deviceActivity,
            uptime: uptime
        ).isEmpty else { return }

        deviceActivityRecoveryTask = Task { [weak self] in
            guard let self else { return }
            let restored = await self.attemptHIDWakeRecovery()
            self.deviceActivityRecoveryTask = nil
            if restored {
                self.finishHIDWakeRecovery()
            }
        }
    }

    private func attemptHIDWakeRecovery() async -> Bool {
        guard !hidRecoveryInProgress else { return false }
        hidRecoveryInProgress = true
        defer { hidRecoveryInProgress = false }
        return await refreshHIDPPIdentity(reapplySettings: true)
    }

    private func finishHIDWakeRecovery() {
        awaitingHIDWakeRecovery = false
        recoveryPlanner.markHIDSettingsRestored()
        synchronizeEventTap()
    }

    private func persistSetting(_ key: String, value: JSONValue) {
        guard !isApplyingSnapshot, !isApplyingHIDState else { return }
        persist(.setting(key: key, value: value), key: "setting.\(key)")
    }

    private func persist(
        _ mutation: MouserConfigMutation,
        key: String,
        delay: Duration = .milliseconds(180)
    ) {
        guard let configStore else { return }
        pendingWrites[key]?.cancel()
        pendingWrites[key] = Task { [weak self] in
            do {
                if delay != .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                try await configStore.update(mutation)
                guard !Task.isCancelled else { return }
                self?.configurationLoaded = true
                self?.configurationStatus = "更改已保存"
            } catch is CancellationError {
                return
            } catch {
                self?.configurationStatus = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    static func live(
        configStore: MouserConfigStore = MouserConfigStore(),
        accessibilityAuthorizer: any AccessibilityAuthorizing = SystemAccessibilityAuthorizer(),
        eventTap: any ScrollEventTapping = CoreGraphicsScrollEventTap(),
        loginItemController: any LoginItemControlling = SystemLoginItemController()
    ) -> WorkspaceModel {
        WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: false,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 25,
            scrollForce: 50,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: true,
            hapticStrength: 2,
            appearanceMode: .system,
            profiles: Self.fallbackProfiles,
            configStore: configStore,
            accessibilityAuthorizer: accessibilityAuthorizer,
            eventTap: eventTap,
            loginItemController: loginItemController,
            deviceDiscovery: CoreHIDLogitechDeviceDiscovery(),
            nativeHIDProbeEnabled: UserDefaults.standard.object(
                forKey: "nativeHIDProbeEnabled"
            ) as? Bool ?? true,
            nativeEventTapEnabled: UserDefaults.standard.object(
                forKey: "nativeEventTapEnabled"
            ) as? Bool ?? false
        )
    }

    static var preview: WorkspaceModel {
        let defaultMappings = [
            ButtonMapping(button: .middle, action: .missionControl),
            ButtonMapping(button: .modeShift, action: .switchScrollMode),
            ButtonMapping(button: .back, action: .browserBack),
            ButtonMapping(button: .forward, action: .browserForward),
            ButtonMapping(button: .gesture, action: .missionControl),
        ]
        let finderMappings = [
            ButtonMapping(button: .middle, action: .missionControl),
            ButtonMapping(button: .modeShift, action: .switchScrollMode),
            ButtonMapping(button: .back, action: .paste),
            ButtonMapping(button: .forward, action: .browserForward),
            ButtonMapping(button: .gesture, action: .missionControl),
        ]
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 82,
            dpi: 1000,
            smartShiftEnabled: true,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 25,
            scrollForce: 50,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: true,
            hapticStrength: 1.68,
            appearanceMode: .system,
            language: .simplifiedChinese,
            startAtLogin: true,
            actionsRingHoldMilliseconds: 420,
            actionsRingUsesGlobalSlots: false,
            actionsRingGlobalSlots: [
                MouserAction.missionControl.rawValue,
                MouserAction.browserForward.rawValue,
                MouserAction.copy.rawValue,
                MouserAction.paste.rawValue,
                MouserAction.showDesktop.rawValue,
                MouserAction.browserBack.rawValue,
                MouserAction.screenshotRegionFile.rawValue,
                MouserAction.playPause.rawValue,
            ],
            profiles: [
                AppProfile(id: "default", name: "默认配置", bundleID: nil, systemImage: "square.grid.2x2", mappings: defaultMappings),
                AppProfile(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome", systemImage: "globe", mappings: finderMappings),
                AppProfile(id: "code", name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", systemImage: "chevron.left.forwardslash.chevron.right", mappings: defaultMappings),
                AppProfile(id: "vlc", name: "VLC", bundleID: "org.videolan.vlc", systemImage: "play.rectangle", mappings: defaultMappings),
                AppProfile(id: "finder", name: "Finder", bundleID: "com.apple.finder", systemImage: "face.smiling", mappings: finderMappings),
                AppProfile(id: "safari", name: "Safari", bundleID: "com.apple.Safari", systemImage: "safari", mappings: defaultMappings),
            ]
        )
        model.deviceName = "MX Master 3S"
        model.deviceTransport = "Logi Bolt"
        model.configurationLoaded = true
        return model
    }

    private static var fallbackProfiles: [AppProfile] {
        let mappings = MouseButton.allCases.map {
            ButtonMapping(button: $0, action: .passThrough)
        }
        return [
            AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "square.grid.2x2",
                mappings: mappings
            ),
        ]
    }
}
