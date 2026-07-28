import AppKit
import Testing
@testable import MouserNative

private final class WorkspaceTestEventTap: ScrollEventTapping {
    var state: ScrollEventTapState = .stopped
    private(set) var settings: [ScrollInversionSettings] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var rebuildCount = 0
    private(set) var buttonMappings: [MouseButton: String] = [:]
    private(set) var supplementalMappings: [String: String] = [:]
    private(set) var horizontalScrollThresholds: [Double] = []
    private(set) var externalGestureBegins: [MouseButton] = []
    private(set) var externalGestureEnds: [MouseButton] = []
    private var buttonActionHandler: (@Sendable (MappedActionInvocation) -> Void)?
    private var deviceActivityHandler: (@Sendable () -> Void)?

    func updateSettings(_ settings: ScrollInversionSettings) {
        self.settings.append(settings)
    }

    func updateHorizontalScrollThreshold(_ threshold: Double) {
        horizontalScrollThresholds.append(threshold)
    }

    func updateButtonMappings(
        _ mappings: [MouseButton: String],
        gestureMappings: [String: String],
        actionHandler: @escaping @Sendable (MappedActionInvocation) -> Void
    ) {
        supplementalMappings = gestureMappings
        buttonMappings = mappings
        buttonActionHandler = actionHandler
    }

    func updateDeviceActivityHandler(
        _ handler: @escaping @Sendable () -> Void
    ) {
        deviceActivityHandler = handler
    }

    func simulateDeviceActivity() {
        deviceActivityHandler?()
    }

    func simulateMappedAction(_ actionID: String, buttonID: String = "xbutton1") {
        buttonActionHandler?(
            MappedActionInvocation(actionID: actionID, buttonID: buttonID, kind: .press)
        )
    }

    func beginExternalGesture(for button: MouseButton) {
        externalGestureBegins.append(button)
    }

    func endExternalGesture(for button: MouseButton) {
        externalGestureEnds.append(button)
    }

    @discardableResult
    func start() -> Bool {
        if state == .running { return true }
        startCount += 1
        state = .running
        return true
    }

    func stop() {
        stopCount += 1
        state = .stopped
    }

    @discardableResult
    func rebuild() -> Bool {
        rebuildCount += 1
        state = .running
        return true
    }
}

private final class WorkspaceActionExecutor: MouserActionExecuting, @unchecked Sendable {
    private(set) var actions: [String] = []

    func execute(actionID: String) -> Bool {
        actions.append(actionID)
        return true
    }
}

private actor WorkspaceScreenshotCapturer: ScreenshotCapturing {
    struct Request: Equatable, Sendable {
        let action: MouserAction
        let directoryURL: URL
    }

    private(set) var requests: [Request] = []

    func capture(_ action: MouserAction, directoryURL: URL) async throws -> URL {
        requests.append(.init(action: action, directoryURL: directoryURL))
        return directoryURL.appending(path: "Screenshot.png")
    }
}

@MainActor
private final class WorkspaceActionsRingOverlay: ActionsRingOverlayPresenting {
    struct Show: Equatable {
        let slots: [String]
        let highlightedIndex: Int?
        let interactive: Bool
    }

    private(set) var shows: [Show] = []
    private(set) var highlights: [Int?] = []
    private(set) var hideCount = 0
    private var onSelect: (@MainActor (Int) -> Void)?
    private var onDismiss: (@MainActor () -> Void)?

    func show(
        slots: [String],
        highlightedIndex: Int?,
        interactive: Bool,
        language: AppLanguage,
        at screenPoint: NSPoint,
        onSelect: @escaping @MainActor (Int) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        _ = (language, screenPoint)
        shows.append(.init(
            slots: slots,
            highlightedIndex: highlightedIndex,
            interactive: interactive
        ))
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    func updateHighlight(_ index: Int?) {
        highlights.append(index)
    }

    func hide() {
        hideCount += 1
    }

    func select(_ index: Int) {
        onSelect?(index)
    }

    func dismiss() {
        onDismiss?()
    }
}

@Suite("Haptic trigger routing")
struct HapticTriggerRouterTests {
    @Test("action and button allowlists are combined with an OR gate")
    func combinesAllowlists() {
        var router = HapticTriggerRouter(
            enabled: true,
            actionIDs: [MouserAction.playPause.rawValue],
            buttonIDs: [MouseButton.back.configID],
            deduplicates: true
        )

        #expect(
            router.waveform(
                for: .init(actionID: "copy", buttonID: "xbutton1", kind: .press),
                uptime: 1
            ) == 1
        )
        #expect(
            router.waveform(
                for: .init(actionID: "play_pause", buttonID: "middle", kind: .press),
                uptime: 1.2
            ) == 1
        )
        #expect(
            router.waveform(
                for: .init(actionID: "copy", buttonID: "middle", kind: .press),
                uptime: 1.4
            ) == nil
        )
    }

    @Test("gesture and DPI actions select the Python waveform IDs")
    func selectsWaveforms() {
        var router = HapticTriggerRouter(
            enabled: true,
            actionIDs: [MouserAction.cycleDPI.rawValue],
            buttonIDs: [MouseButton.gesture.configID],
            deduplicates: false
        )

        #expect(
            router.waveform(
                for: .init(actionID: "cycle_dpi", buttonID: "middle", kind: .press),
                uptime: 1
            ) == 3
        )
        #expect(
            router.waveform(
                for: .init(actionID: "copy", buttonID: "gesture", kind: .gesture),
                uptime: 1
            ) == 7
        )
    }

    @Test("deduplication suppresses pulses for 100 milliseconds and horizontal scroll never pulses")
    func deduplicatesAndExcludesHorizontalScroll() {
        var router = HapticTriggerRouter(
            enabled: true,
            actionIDs: [MouserAction.playPause.rawValue],
            buttonIDs: [],
            deduplicates: true
        )
        let press = MappedActionInvocation(
            actionID: "play_pause",
            buttonID: "middle",
            kind: .press
        )

        #expect(router.waveform(for: press, uptime: 1) == 1)
        #expect(router.waveform(for: press, uptime: 1.05) == nil)
        #expect(router.waveform(for: press, uptime: 1.101) == 1)
        #expect(
            router.waveform(
                for: .init(
                    actionID: "play_pause",
                    buttonID: "hscroll_right",
                    kind: .horizontalScroll
                ),
                uptime: 2
            ) == nil
        )
    }
}

@MainActor
private final class TrustedWorkspaceAuthorizer: AccessibilityAuthorizing {
    func isTrusted(prompt: Bool) -> Bool { true }
}

private actor WorkspaceHIDDiscovery: LogitechDeviceDiscovering {
    let identity: HIDPPDeviceIdentity?
    let controller: (any HIDPPDeviceControlling)?
    private(set) var identifyCount = 0

    init(
        identity: HIDPPDeviceIdentity?,
        controller: (any HIDPPDeviceControlling)? = nil
    ) {
        self.identity = identity
        self.controller = controller
    }

    nonisolated func updates() -> AsyncStream<[LogitechHIDDevice]> {
        AsyncStream { $0.finish() }
    }

    func identify(_ device: LogitechHIDDevice) -> HIDPPDeviceIdentity? {
        identifyCount += 1
        return identity
    }

    func controller(
        for device: LogitechHIDDevice,
        identity: HIDPPDeviceIdentity
    ) -> (any HIDPPDeviceControlling)? {
        controller
    }
}

private actor RecoveringWorkspaceHIDDiscovery: LogitechDeviceDiscovering {
    let identity: HIDPPDeviceIdentity
    let controller: any HIDPPDeviceControlling
    private(set) var identifyCount = 0
    private var available = false

    init(
        identity: HIDPPDeviceIdentity,
        controller: any HIDPPDeviceControlling
    ) {
        self.identity = identity
        self.controller = controller
    }

    nonisolated func updates() -> AsyncStream<[LogitechHIDDevice]> {
        AsyncStream { $0.finish() }
    }

    func identify(_ device: LogitechHIDDevice) -> HIDPPDeviceIdentity? {
        _ = device
        identifyCount += 1
        return available ? identity : nil
    }

    func controller(
        for device: LogitechHIDDevice,
        identity: HIDPPDeviceIdentity
    ) -> (any HIDPPDeviceControlling)? {
        _ = (device, identity)
        return controller
    }

    func makeDeviceAvailable() {
        available = true
    }
}

private actor WorkspaceHIDController: HIDPPDeviceControlling {
    enum Call: Equatable {
        case dpi(Int)
        case smartShift(SmartShiftMode, Bool, Int, Int)
        case vertical(Bool)
        case horizontal(Bool)
        case haptic(Int)
        case waveform(Int)
        case forceSensing(Int)
    }

    let state: HIDPPDeviceState
    let specialEvents: [HIDPPButtonEvent]
    let specialInputs: [HIDPPSpecialInputEvent]
    let specialInputDelaysMilliseconds: [Int]
    private(set) var calls: [Call] = []
    private(set) var specialButtonRequests: [Set<MouseButton>] = []
    private(set) var rawXYButtonRequests: [Set<MouseButton>] = []

    init(
        state: HIDPPDeviceState,
        specialEvents: [HIDPPButtonEvent] = [],
        specialInputs: [HIDPPSpecialInputEvent] = [],
        specialInputDelaysMilliseconds: [Int] = []
    ) {
        self.state = state
        self.specialEvents = specialEvents
        self.specialInputs = specialInputs
        self.specialInputDelaysMilliseconds = specialInputDelaysMilliseconds
    }

    func readState(timeout: Duration) -> HIDPPDeviceState { state }

    func setDPI(_ dpi: Int, timeout: Duration) {
        calls.append(.dpi(dpi))
    }

    func setSmartShift(
        mode: SmartShiftMode,
        automatic: Bool,
        threshold: Int,
        scrollForce: Int,
        timeout: Duration
    ) {
        calls.append(.smartShift(mode, automatic, threshold, scrollForce))
    }

    func setVerticalScrollInverted(_ inverted: Bool, timeout: Duration) {
        calls.append(.vertical(inverted))
    }

    func setHorizontalScrollInverted(_ inverted: Bool, timeout: Duration) {
        calls.append(.horizontal(inverted))
    }

    func setHapticLevel(_ level: Int, timeout: Duration) {
        calls.append(.haptic(level))
    }

    func playHapticWaveform(_ waveformID: Int, timeout: Duration) {
        calls.append(.waveform(waveformID))
    }

    func setForceSensing(_ value: Int, timeout: Duration) {
        calls.append(.forceSensing(value))
    }

    func specialButtonEvents(
        for buttons: Set<MouseButton>,
        timeout: Duration
    ) -> AsyncThrowingStream<HIDPPButtonEvent, any Error> {
        _ = timeout
        specialButtonRequests.append(buttons)
        let events = specialEvents
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func specialInputEvents(
        for buttons: Set<MouseButton>,
        rawXYButtons: Set<MouseButton>,
        timeout: Duration
    ) -> AsyncThrowingStream<HIDPPSpecialInputEvent, any Error> {
        _ = timeout
        specialButtonRequests.append(buttons)
        rawXYButtonRequests.append(rawXYButtons)
        let inputs = specialInputs.isEmpty
            ? specialEvents.map(HIDPPSpecialInputEvent.button)
            : specialInputs
        let delays = specialInputDelaysMilliseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, input) in inputs.enumerated() {
                    if delays.indices.contains(index), delays[index] > 0 {
                        try? await Task.sleep(for: .milliseconds(delays[index]))
                    }
                    guard !Task.isCancelled else { break }
                    continuation.yield(input)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("Workspace navigation and presentation")
@MainActor
struct WorkspaceModelTests {
    @Test("manual mouse artwork override preserves discovered hardware DPI range")
    func manualDeviceLayoutOverrideIsVisualOnly() {
        let model = WorkspaceModel.preview
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 1,
                productID: 0xB034,
                productName: "MX Master 3S",
                transport: "Bluetooth Low Energy"
            ),
        ])

        #expect(model.dpiRange == 200...8_000)
        model.setDeviceLayoutOverride("mx_vertical")

        #expect(model.deviceLayoutOverrideKey == "mx_vertical")
        #expect(model.deviceProfile.imageResource == "mx_vertical")
        #expect(model.dpiRange == 200...8_000)
    }

    @Test("menu-bar pause stops and resumes native remapping")
    func remappingCanBePausedAndResumed() {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 50,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            eventTap: eventTap
        )

        model.setNativeEventTapEnabled(true)
        #expect(eventTap.state == .running)

        model.setRemappingEnabled(false)
        #expect(!model.remappingEnabled)
        #expect(eventTap.state == .stopped)

        model.setRemappingEnabled(true)
        #expect(model.remappingEnabled)
        #expect(eventTap.state == .running)
    }

    @Test("macOS wheel inversion fallback runs alongside HID device control")
    func macOSWheelFallbackRunsWithHIDControl() {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 50,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            wheelInversionBackend: .macOS,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            eventTap: eventTap
        )

        model.setNativeHIDProbeEnabled(true)

        #expect(model.nativeHIDProbeEnabled)
        #expect(eventTap.startCount == 1)
        #expect(eventTap.settings.last == .init(
            invertVertical: true,
            invertHorizontal: false,
            ignoreTrackpad: true
        ))
    }

    @Test("debug mode records mapped actions and can be cleared")
    func debugModeRecordsActions() async {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 50,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            eventTap: eventTap
        )

        eventTap.simulateMappedAction(MouserAction.copy.rawValue)
        await Task.yield()
        #expect(model.debugLogText.isEmpty)

        model.debugMode = true
        eventTap.simulateMappedAction(MouserAction.copy.rawValue, buttonID: "xbutton1")
        for _ in 0..<20 where !model.debugLogText.contains("copy") { await Task.yield() }
        #expect(model.debugLogText.contains("xbutton1"))

        model.clearDebugLog()
        #expect(model.debugLogText.isEmpty)
    }

    @Test("cycle DPI follows the four user-configured presets")
    func cycleDPIUsesConfiguredPresets() async {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 50,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            dpiPresets: [800, 1200, 1600, 2400],
            profiles: [],
            eventTap: eventTap
        )

        eventTap.simulateMappedAction(MouserAction.cycleDPI.rawValue)
        for _ in 0..<20 where model.dpi == 1000 { await Task.yield() }
        #expect(model.dpi == 800)

        model.dpi = 1200
        eventTap.simulateMappedAction(MouserAction.cycleDPI.rawValue)
        for _ in 0..<20 where model.dpi == 1200 { await Task.yield() }
        #expect(model.dpi == 1600)
    }

    @Test("custom screenshot folder routes file actions to native capture")
    func customScreenshotFolderRoutesFileActions() async {
        let eventTap = WorkspaceTestEventTap()
        let actionExecutor = WorkspaceActionExecutor()
        let screenshotCapturer = WorkspaceScreenshotCapturer()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            screenshotDirectory: "/tmp/Mouser Screenshots",
            profiles: [],
            eventTap: eventTap,
            actionExecutor: actionExecutor,
            screenshotCapturer: screenshotCapturer
        )

        eventTap.simulateMappedAction(MouserAction.screenshotRegionFile.rawValue)
        for _ in 0..<20 where await screenshotCapturer.requests.isEmpty {
            await Task.yield()
        }

        #expect(await screenshotCapturer.requests == [
            .init(
                action: .screenshotRegionFile,
                directoryURL: URL(filePath: "/tmp/Mouser Screenshots", directoryHint: .isDirectory)
            ),
        ])
        #expect(actionExecutor.actions.isEmpty)
        #expect(model.screenshotStatusText.contains("Screenshot.png"))
    }

    @Test("system screenshot location keeps the existing shortcut executor")
    func systemScreenshotLocationKeepsShortcutExecutor() async {
        let eventTap = WorkspaceTestEventTap()
        let actionExecutor = WorkspaceActionExecutor()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            eventTap: eventTap,
            actionExecutor: actionExecutor
        )
        #expect(!model.hasCustomScreenshotDirectory)

        eventTap.simulateMappedAction(MouserAction.screenshotFullFile.rawValue)
        for _ in 0..<20 where actionExecutor.actions.isEmpty {
            await Task.yield()
        }

        #expect(actionExecutor.actions == [MouserAction.screenshotFullFile.rawValue])
    }

    @Test("application profiles inherit defaults, reject duplicates, and delete safely")
    func applicationProfileLifecycle() async {
        let model = WorkspaceModel.preview
        let candidate = ApplicationProfileCandidate(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari.Test",
            applicationPath: "/Applications/Safari Test.app"
        )

        #expect(model.addApplicationProfile(candidate))
        let createdID = model.selectedProfileID
        #expect(model.selectedProfile?.name == "Safari")
        #expect(model.selectedProfile?.appIdentifiers.contains("com.apple.Safari.Test") == true)
        #expect(!model.addApplicationProfile(candidate))

        #expect(model.deleteProfile(id: createdID))
        #expect(model.selectedProfileID == "default")
        #expect(!model.deleteProfile(id: "default"))
    }

    @Test("diagnostics describe runtime state without exporting configuration contents")
    func diagnosticsReportIsSafeAndUseful() {
        let model = WorkspaceModel.preview

        let report = model.diagnosticReport

        #expect(report.contains("Mouser Diagnostics"))
        #expect(report.contains("Accessibility:"))
        #expect(report.contains("Device:"))
        #expect(!report.contains("future_setting"))
        #expect(!report.contains("Apple ID"))
    }

    @Test("primary sections keep the simple task order")
    func primarySectionsKeepTheSimpleTaskOrder() {
        #expect(
            WorkspaceSection.allCases ==
                [
                    .overview, .buttons, .pointerAndScroll, .haptics,
                    .actionsRing, .profiles, .advanced,
                ]
        )
    }

    @Test("selecting a profile keeps the current section")
    func selectingAProfileKeepsTheCurrentSection() {
        let model = WorkspaceModel.preview
        model.selectedSection = .pointerAndScroll

        model.selectProfile(id: "finder")

        #expect(model.selectedProfileID == "finder")
        #expect(model.selectedSection == .pointerAndScroll)
    }

    @Test("foreground application switches to its profile and falls back to default")
    func foregroundApplicationSelectsProfile() {
        let model = WorkspaceModel.preview

        model.handleForegroundApplication(bundleIdentifier: "com.apple.Safari")
        #expect(model.selectedProfileID == "safari")

        model.handleForegroundApplication(bundleIdentifier: "com.example.Unconfigured")
        #expect(model.selectedProfileID == "default")
    }

    @Test("button summaries use the selected profile")
    func buttonMappingSummaryUsesTheSelectedProfile() {
        let model = WorkspaceModel.preview
        model.selectProfile(id: "finder")

        #expect(model.mapping(for: .back)?.action == .paste)
    }

    @Test("gesture mode and each gesture slot update the in-memory profile")
    func gestureMappingsCanBeEdited() {
        let model = WorkspaceModel.preview

        model.setActionID("gesture_swipe", for: .gesture)
        model.setGestureAction(.copy, for: .gesture, slot: .left)
        model.setGestureAction(.appExpose, for: .gesture, slot: .tap)

        #expect(model.selectedProfile?.mappingValue(for: "gesture") == "gesture_swipe")
        #expect(model.selectedProfile?.mappingValue(for: "gesture_left") == "copy")
        #expect(model.selectedProfile?.mappingValue(for: "gesture_tap") == "app_expose")
    }

    @Test("permission callout only appears when Accessibility is missing")
    func permissionCalloutOnlyAppearsWhenAccessibilityIsMissing() {
        let model = WorkspaceModel.preview
        model.accessibilityGranted = false
        #expect(model.showsPermissionCallout)

        model.accessibilityGranted = true
        #expect(!model.showsPermissionCallout)
    }

    @Test("system appearance does not force a color scheme")
    func appearanceModeLeavesSystemUnforcedByDefault() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test("native event interception is opt-in and follows current scroll settings")
    func nativeEventInterceptionIsOptIn() {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1000,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap
        )

        #expect(eventTap.startCount == 0)
        model.setNativeEventTapEnabled(true)

        #expect(eventTap.startCount == 1)
        #expect(eventTap.settings.last == .init(
            invertVertical: true,
            invertHorizontal: false,
            ignoreTrackpad: true
        ))

        model.setNativeEventTapEnabled(false)
        #expect(eventTap.stopCount == 1)
    }

    @Test("firmware and event-tap scroll inversion cannot be enabled together")
    func nativeScrollEnginesAreMutuallyExclusive() {
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 80,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap
        )

        model.setNativeEventTapEnabled(true)
        model.setNativeHIDProbeEnabled(true)

        #expect(model.nativeHIDProbeEnabled)
        #expect(!model.nativeEventTapEnabled)
        #expect(eventTap.stopCount == 1)

        model.setNativeEventTapEnabled(true)
        #expect(model.nativeEventTapEnabled)
        #expect(!model.nativeHIDProbeEnabled)
    }

    @Test("horizontal scroll mappings start the event tap without inversion enabled")
    func horizontalScrollMappingStartsEventTap() {
        let eventTap = WorkspaceTestEventTap()
        let profile = AppProfile(
            id: "default",
            name: "默认",
            bundleID: nil,
            systemImage: "square.grid.2x2",
            mappings: MouseButton.allCases.map {
                ButtonMapping(button: $0, action: .passThrough)
            }
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 80,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [profile],
            eventTap: eventTap
        )

        model.setSupplementalActionID(
            MouserAction.nextDesktop.rawValue,
            for: "hscroll_right"
        )

        #expect(
            model.supplementalActionID(for: "hscroll_right")
                == MouserAction.nextDesktop.rawValue
        )
        #expect(
            eventTap.supplementalMappings["hscroll_right"]
                == MouserAction.nextDesktop.rawValue
        )
        #expect(eventTap.startCount == 1)
        #expect(eventTap.state == .running)
    }

    @Test("selected profile mappings are installed in the event tap and execute actions")
    func selectedMappingsDriveTheActionExecutor() async {
        let eventTap = WorkspaceTestEventTap()
        let executor = WorkspaceActionExecutor()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(button: $0, action: $0 == .back ? .copy : .passThrough)
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 80,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap,
            actionExecutor: executor
        )
        await model.bootstrap()

        #expect(eventTap.buttonMappings[.back] == MouserAction.copy.rawValue)
        #expect(eventTap.startCount == 1)
        eventTap.simulateMappedAction(MouserAction.copy.rawValue)
        await Task.yield()

        #expect(executor.actions == [MouserAction.copy.rawValue])
        _ = model
    }

    @Test("native HID probing is opt-in and replaces receiver placeholders with real identity")
    func nativeHIDProbingIsOptIn() async {
        let discovery = WorkspaceHIDDiscovery(identity: HIDPPDeviceIdentity(
            deviceIndex: 0x02,
            name: "MX Master 3S",
            featureIndexes: [.reprogrammableControlsV4: 0x05, .adjustableDPI: 0x09]
        ))
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: true,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: discovery,
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()

        #expect(model.mouseConnected)
        #expect(model.deviceName == "MX Master 3S")
        #expect(model.hidppStatusText == "已识别 · 接收器槽位 2")
        #expect(model.batteryText == "—")
        #expect(await discovery.identifyCount == 1)
    }

    @Test("removing the HID interface releases the stale native controller")
    func deviceRemovalClearsNativeController() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: 1200,
            smartShift: nil,
            battery: nil,
            verticalScrollInverted: nil
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3S",
            featureIndexes: [.adjustableDPI: 0x09]
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1200,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])
        await model.refreshHIDPPIdentity()
        #expect(model.nativeHIDControlConnected)

        model.applyDetectedDevices([])
        #expect(!model.nativeHIDControlConnected)
        #expect(model.hidppStatusText == "等待 HID++ 接口")

        await model.refreshHIDPPIdentity()
        #expect(!model.nativeHIDControlConnected)
    }

    @Test("native HID connection reads hardware state and sends debounced user settings")
    func nativeHIDConnectionSynchronizesSettings() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: 1800,
            smartShift: HIDPPSmartShiftState(
                mode: .ratchet,
                automatic: true,
                threshold: 30,
                scrollForce: 55
            ),
            battery: HIDPPBatteryState(level: 82, charging: true),
            verticalScrollInverted: true
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
                .batteryStatus: 0x08,
            ]
        )
        let discovery = WorkspaceHIDDiscovery(identity: identity, controller: controller)
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 25,
            scrollForce: 50,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: discovery,
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()

        #expect(model.dpi == 1800)
        #expect(model.smartShiftEnabled)
        #expect(model.smartShiftMode == .ratchet)
        #expect(model.smartShiftThreshold == 30)
        #expect(model.scrollForce == 55)
        #expect(model.batteryLevel == 82)
        #expect(model.batteryCharging)
        #expect(model.batteryStatusText == "82% · 充电中")
        #expect(model.invertVerticalScroll)
        #expect(await controller.calls.isEmpty)

        model.dpi = 2000
        model.smartShiftMode = .freeSpin
        model.smartShiftEnabled = false
        model.invertHorizontalScroll = true
        await model.flushPendingHIDWrites()

        let calls = await controller.calls
        #expect(calls.contains(.dpi(2000)))
        #expect(calls.contains(.smartShift(.freeSpin, false, 30, 55)))
        #expect(calls.contains(.horizontal(true)))
    }

    @Test("session recovery reconnects and reapplies configured hardware settings")
    func nativeHIDRecoveryReappliesSettings() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: nil,
            smartShift: nil,
            battery: nil,
            verticalScrollInverted: nil
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
            ]
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 25,
            scrollForce: 50,
            invertVerticalScroll: true,
            invertHorizontalScroll: true,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity(reapplySettings: true)

        #expect(await controller.calls == [
            .dpi(1600),
            .smartShift(.ratchet, false, 25, 50),
            .vertical(true),
            .horizontal(true),
        ])
        #expect(model.hidppStatusText == "已恢复设备设置")
    }

    @Test("mouse activity after late wake reapplies settings after unlock retries missed")
    func lateMouseWakeReappliesSettingsOnDeviceActivity() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: nil,
            smartShift: nil,
            battery: nil,
            verticalScrollInverted: nil
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
            ]
        )
        let discovery = RecoveringWorkspaceHIDDiscovery(
            identity: identity,
            controller: controller
        )
        let eventTap = WorkspaceTestEventTap()
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 10,
            scrollForce: 10,
            invertVerticalScroll: true,
            invertHorizontalScroll: true,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap,
            deviceDiscovery: discovery,
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        model.handleSessionRecoverySignal(.screenUnlock)
        for _ in 0..<50 where await discovery.identifyCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await controller.calls.isEmpty)
        #expect(eventTap.state == .running)

        await discovery.makeDeviceAvailable()
        eventTap.simulateDeviceActivity()
        for _ in 0..<50 where await controller.calls.count < 4 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(await controller.calls == [
            .dpi(1600),
            .smartShift(.ratchet, false, 10, 10),
            .vertical(true),
            .horizontal(true),
        ])
    }

    @Test("HID re-enumeration after unlock reapplies config instead of importing reset state")
    func reenumerationAfterUnlockReappliesConfiguredState() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: 800,
            smartShift: HIDPPSmartShiftState(
                mode: .freeSpin,
                automatic: false,
                threshold: 25,
                scrollForce: 50
            ),
            battery: nil,
            verticalScrollInverted: false
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
            ]
        )
        let discovery = RecoveringWorkspaceHIDDiscovery(
            identity: identity,
            controller: controller
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: true,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 10,
            scrollForce: 10,
            invertVerticalScroll: true,
            invertHorizontalScroll: true,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: discovery,
            nativeHIDProbeEnabled: true
        )
        let receiver = LogitechHIDDevice(
            id: 2,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB",
            usagePage: 0xFF00,
            usage: 1
        )
        model.applyDetectedDevices([receiver])
        model.handleSessionRecoverySignal(.screenUnlock)
        for _ in 0..<50 where await discovery.identifyCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        await discovery.makeDeviceAvailable()
        model.handleDetectedDevicesUpdate([receiver])
        for _ in 0..<50 where await controller.calls.count < 4 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.dpi == 1600)
        #expect(model.smartShiftMode == .ratchet)
        #expect(model.smartShiftThreshold == 10)
        #expect(model.scrollForce == 10)
        #expect(await controller.calls == [
            .dpi(1600),
            .smartShift(.ratchet, false, 10, 10),
            .vertical(true),
            .horizontal(true),
        ])
    }

    @Test("initial HID discovery restores persisted settings instead of importing device defaults")
    func initialHIDDiscoveryRestoresPersistedSettings() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: 1000,
            smartShift: HIDPPSmartShiftState(
                mode: .ratchet,
                automatic: true,
                threshold: 10,
                scrollForce: 10
            ),
            battery: nil,
            verticalScrollInverted: false
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3",
            featureIndexes: [
                .adjustableDPI: 0x0C,
                .smartShift: 0x0D,
                .highResolutionWheelEnhanced: 0x0E,
                .thumbWheel: 0x0F,
            ]
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftMode: .ratchet,
            smartShiftThreshold: 10,
            scrollForce: 10,
            invertVerticalScroll: true,
            invertHorizontalScroll: true,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: WorkspaceHIDDiscovery(
                identity: identity,
                controller: controller
            ),
            nativeHIDProbeEnabled: true
        )

        model.handleDetectedDevicesUpdate([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])
        for _ in 0..<50 where await controller.calls.count < 4 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.dpi == 1600)
        #expect(model.smartShiftMode == .ratchet)
        #expect(model.smartShiftThreshold == 10)
        #expect(model.scrollForce == 10)
        #expect(await controller.calls == [
            .dpi(1600),
            .smartShift(.ratchet, false, 10, 10),
            .vertical(true),
            .horizontal(true),
        ])
    }

    @Test("haptic controls write through to hardware and preview a waveform")
    func nativeHapticControlsAreLive() async {
        let controller = WorkspaceHIDController(state: HIDPPDeviceState(
            dpi: nil,
            smartShift: nil,
            battery: nil,
            verticalScrollInverted: nil
        ))
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 4",
            featureIndexes: [.haptic: 0x12]
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: true,
            hapticStrength: 2,
            appearanceMode: .system,
            profiles: [],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])
        await model.refreshHIDPPIdentity()

        #expect(model.hapticSupported)
        model.hapticStrength = 3
        await model.flushPendingHIDWrites()
        await model.playHapticPreview()

        #expect(await controller.calls == [.haptic(3), .waveform(0)])
    }

    @Test("diverted mode shift and gesture presses execute selected profile actions")
    func nativeSpecialButtonsExecuteMappings() async {
        let controller = WorkspaceHIDController(
            state: HIDPPDeviceState(
                dpi: nil,
                smartShift: nil,
                battery: nil,
                verticalScrollInverted: nil
            ),
            specialEvents: [
                .init(button: .modeShift, isPressed: true),
                .init(button: .modeShift, isPressed: false),
                .init(button: .gesture, isPressed: true),
            ]
        )
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3S",
            featureIndexes: [.reprogrammableControlsV4: 0x05]
        )
        let executor = WorkspaceActionExecutor()
        let mappings = MouseButton.allCases.map { button -> ButtonMapping in
            let action: MouserAction = switch button {
            case .modeShift: .copy
            case .gesture: .paste
            default: .passThrough
            }
            return ButtonMapping(button: button, action: action)
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            actionExecutor: executor,
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()
        for _ in 0..<20 where executor.actions.count < 2 { await Task.yield() }

        #expect(await controller.specialButtonRequests == [[.modeShift, .gesture]])
        #expect(executor.actions == [MouserAction.copy.rawValue, MouserAction.paste.rawValue])
    }

    @Test("RawXY gesture swipe executes its directional mapping instead of tap")
    func nativeGestureSwipeExecutesDirection() async {
        var inputs: [HIDPPSpecialInputEvent] = [
            .button(.init(button: .gesture, isPressed: true)),
        ]
        inputs += Array(repeating: .movement(dx: -10, dy: 0), count: 7)
        inputs.append(.button(.init(button: .gesture, isPressed: false)))
        let controller = WorkspaceHIDController(
            state: HIDPPDeviceState(
                dpi: nil,
                smartShift: nil,
                battery: nil,
                verticalScrollInverted: nil
            ),
            specialInputs: inputs
        )
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3S",
            featureIndexes: [.reprogrammableControlsV4: 0x05]
        )
        let executor = WorkspaceActionExecutor()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(button: $0, actionID: $0 == .gesture ? "gesture_swipe" : "none")
        }
        let profile = AppProfile(
            id: "default",
            name: "默认",
            bundleID: nil,
            systemImage: "mouse",
            mappings: mappings,
            supplementalMappings: [
                "gesture_tap": MouserAction.appExpose.rawValue,
                "gesture_left": MouserAction.copy.rawValue,
                "gesture_right": MouserAction.paste.rawValue,
                "gesture_up": MouserAction.missionControl.rawValue,
                "gesture_down": MouserAction.showDesktop.rawValue,
            ]
        )
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [profile],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            actionExecutor: executor,
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()
        for _ in 0..<30 where executor.actions.isEmpty { await Task.yield() }

        #expect(await controller.rawXYButtonRequests == [[.gesture]])
        #expect(executor.actions == [MouserAction.copy.rawValue])
    }

    @Test("HID mode-shift gesture arms pointer-motion recognition in the event tap")
    func modeShiftGestureUsesPointerMotion() async {
        let controller = WorkspaceHIDController(
            state: HIDPPDeviceState(
                dpi: nil,
                smartShift: nil,
                battery: nil,
                verticalScrollInverted: nil
            ),
            specialEvents: [
                .init(button: .modeShift, isPressed: true),
                .init(button: .modeShift, isPressed: false),
            ]
        )
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 3S",
            featureIndexes: [.reprogrammableControlsV4: 0x05]
        )
        let eventTap = WorkspaceTestEventTap()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(
                button: $0,
                actionID: $0 == .modeShift ? "gesture_swipe" : "none"
            )
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings,
                supplementalMappings: [
                    "mode_shift_tap": MouserAction.copy.rawValue,
                    "mode_shift_left": MouserAction.paste.rawValue,
                ]
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap,
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.setActionID("gesture_swipe", for: .modeShift)
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()
        for _ in 0..<20 where eventTap.externalGestureEnds.isEmpty { await Task.yield() }

        #expect(eventTap.startCount == 1)
        #expect(eventTap.externalGestureBegins == [.modeShift])
        #expect(eventTap.externalGestureEnds == [.modeShift])
        #expect(await controller.rawXYButtonRequests == [[]])
    }

    @Test("MX Vertical exposes and diverts its dedicated DPI switch only")
    func verticalMouseUsesDPISwitch() async {
        let controller = WorkspaceHIDController(
            state: HIDPPDeviceState(
                dpi: nil,
                smartShift: nil,
                battery: nil,
                verticalScrollInverted: nil
            ),
            specialEvents: [.init(button: .dpiSwitch, isPressed: true)]
        )
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Vertical",
            featureIndexes: [.reprogrammableControlsV4: 0x05]
        )
        let executor = WorkspaceActionExecutor()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(
                button: $0,
                action: $0 == .dpiSwitch ? .cycleDPI : .passThrough
            )
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            actionExecutor: executor,
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()
        for _ in 0..<20 {
            if !(await controller.specialButtonRequests).isEmpty { break }
            await Task.yield()
        }

        #expect(model.availableButtons == [.middle, .back, .forward, .dpiSwitch])
        #expect(await controller.specialButtonRequests == [[.dpiSwitch]])
        #expect(model.dpi == 2400)
        #expect(executor.actions.isEmpty)
    }

    @Test("mapped ring action opens an interactive overlay and executes the clicked slot")
    func mappedRingActionUsesInteractiveOverlay() async {
        let eventTap = WorkspaceTestEventTap()
        let executor = WorkspaceActionExecutor()
        let overlay = WorkspaceActionsRingOverlay()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(
                button: $0,
                action: $0 == .back ? .activateActionsRing : .passThrough
            )
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            automaticallyChecksForUpdates: false,
            actionsRingGlobalSlots: [MouserAction.copy.rawValue, MouserAction.paste.rawValue],
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: eventTap,
            actionExecutor: executor,
            actionsRingOverlay: overlay
        )
        await model.bootstrap()

        eventTap.simulateMappedAction(
            MouserAction.activateActionsRing.rawValue,
            buttonID: MouseButton.back.configID
        )
        await Task.yield()

        #expect(overlay.shows == [
            .init(
                slots: [MouserAction.copy.rawValue, MouserAction.paste.rawValue],
                highlightedIndex: nil,
                interactive: true
            ),
        ])
        overlay.select(1)
        #expect(executor.actions == [MouserAction.paste.rawValue])
        #expect(overlay.hideCount >= 2)
    }

    @Test("Sense Panel hold diverts RawXY, highlights a sector, and executes on release")
    func sensePanelHeldRingExecutesSelectedSector() async {
        let controller = WorkspaceHIDController(
            state: HIDPPDeviceState(
                dpi: nil,
                smartShift: nil,
                battery: nil,
                verticalScrollInverted: nil
            ),
            specialInputs: [
                .button(.init(button: .actionsRing, isPressed: true)),
                .movement(dx: 70, dy: 0),
                .button(.init(button: .actionsRing, isPressed: false)),
            ],
            specialInputDelaysMilliseconds: [0, 130, 10]
        )
        let identity = HIDPPDeviceIdentity(
            deviceIndex: 0x01,
            name: "MX Master 4",
            featureIndexes: [.reprogrammableControlsV4: 0x05]
        )
        let executor = WorkspaceActionExecutor()
        let overlay = WorkspaceActionsRingOverlay()
        let mappings = MouseButton.allCases.map {
            ButtonMapping(
                button: $0,
                action: $0 == .actionsRing ? .activateActionsRing : .passThrough
            )
        }
        let model = WorkspaceModel(
            selectedProfileID: "default",
            accessibilityGranted: true,
            mouseConnected: false,
            batteryLevel: 0,
            dpi: 1600,
            smartShiftEnabled: false,
            smartShiftThreshold: 25,
            invertVerticalScroll: false,
            invertHorizontalScroll: false,
            ignoreTrackpad: true,
            hapticsEnabled: false,
            hapticStrength: 0,
            appearanceMode: .system,
            actionsRingHoldMilliseconds: 100,
            actionsRingGlobalSlots: [MouserAction.missionControl.rawValue, MouserAction.copy.rawValue],
            profiles: [AppProfile(
                id: "default",
                name: "默认",
                bundleID: nil,
                systemImage: "mouse",
                mappings: mappings
            )],
            accessibilityAuthorizer: TrustedWorkspaceAuthorizer(),
            eventTap: WorkspaceTestEventTap(),
            actionExecutor: executor,
            actionsRingOverlay: overlay,
            deviceDiscovery: WorkspaceHIDDiscovery(identity: identity, controller: controller),
            nativeHIDProbeEnabled: true
        )
        model.applyDetectedDevices([
            LogitechHIDDevice(
                id: 2,
                productID: 0xC52B,
                productName: "USB Receiver",
                transport: "USB",
                usagePage: 0xFF00,
                usage: 1
            ),
        ])

        await model.refreshHIDPPIdentity()
        for _ in 0..<40 where executor.actions.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(await controller.specialButtonRequests == [[.actionsRing]])
        #expect(await controller.rawXYButtonRequests == [[.actionsRing]])
        #expect(overlay.shows.last?.interactive == false)
        #expect(overlay.highlights == [1])
        #expect(executor.actions == [MouserAction.copy.rawValue])
    }
}
