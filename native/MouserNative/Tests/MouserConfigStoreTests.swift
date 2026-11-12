import Foundation
import Testing
@testable import MouserNative

private let existingConfigFixture = """
{
  "version": 11,
  "active_profile": "finder",
  "future_root": {"kept": true},
  "profiles": {
    "default": {
      "label": "Default (All Apps)",
      "apps": [],
      "mappings": {
        "middle": "none",
        "xbutton1": "mouse_back_click",
        "xbutton2": "mouse_forward_click",
        "mode_shift": "switch_scroll_mode",
        "gesture": "mission_control"
      }
    },
    "finder": {
      "label": "Finder",
      "apps": ["com.apple.finder"],
      "future_profile_value": 42,
      "mappings": {
        "middle": "mission_control",
        "xbutton1": "paste",
        "xbutton2": "browser_forward",
        "mode_shift": "switch_scroll_mode",
        "gesture": "gesture_swipe",
        "gesture_tap": "app_expose",
        "gesture_left": "space_left",
        "gesture_right": "space_right",
        "gesture_up": "mission_control",
        "gesture_down": "show_desktop",
        "hscroll_left": "space_left",
        "hscroll_right": "space_right",
        "actions_ring": "activate_actions_ring",
        "actions_ring_slots": ["copy", "paste", "mission_control", "show_desktop"]
      }
    }
  },
  "settings": {
    "dpi": 1450,
    "dpi_presets": [600, 1000, 1800, 3200],
    "smart_shift_enabled": true,
    "smart_shift_mode": "freespin",
    "smart_shift_threshold": 31,
    "scroll_force": 64,
    "invert_vscroll": true,
    "invert_hscroll": false,
    "ignore_trackpad": true,
    "haptic_enabled": true,
    "haptic_level": 3,
    "action_haptic": ["cycle_dpi", "play_pause"],
    "button_haptic": ["middle", "gesture"],
    "haptic_dedup": false,
    "appearance_mode": "dark",
    "debug_mode": true,
    "device_layout_overrides": {"mx_master_modern": "mx_vertical"},
    "language": "zh_TW",
    "start_minimized": false,
    "start_at_login": false,
    "check_for_updates": false,
    "screenshot_directory": "/tmp/Mouser Screenshots",
    "wheel_divert": "off",
    "gesture_threshold": 32,
    "gesture_commit_window_ms": 450,
    "gesture_settle_ms": 110,
    "gesture_cross_ratio": 0.6,
    "hscroll_threshold": 0.2,
    "actions_ring_hold_ms": 320,
    "actions_ring_hover_haptic": false,
    "actions_ring_use_global": false,
    "actions_ring_slots": ["mission_control", "play_pause", "show_desktop", "launchpad"],
    "future_setting": {"mode": "preserve-me"}
  }
}
"""

@Suite("Mouser configuration compatibility")
struct MouserConfigStoreTests {
    @Test("secure atomic writer publishes complete data with mode 0600")
    func secureAtomicWriterPublishesSecureFile() throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fixture.fileURL.path(percentEncoded: false)
        )

        try SecureAtomicFileWriter().write(Data("{\"updated\":true}".utf8), to: fixture.fileURL)

        #expect(try Data(contentsOf: fixture.fileURL) == Data("{\"updated\":true}".utf8))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path(percentEncoded: false)
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("loads the current Python configuration schema")
    func loadsCurrentSchema() async throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        let snapshot = try await store.load()

        #expect(snapshot.version == 11)
        #expect(snapshot.activeProfileID == "finder")
        #expect(snapshot.dpi == 1450)
        #expect(snapshot.dpiPresets == [600, 1000, 1800, 3200])
        #expect(snapshot.smartShiftEnabled)
        #expect(snapshot.smartShiftMode == .freeSpin)
        #expect(snapshot.scrollForce == 64)
        #expect(snapshot.invertVerticalScroll)
        #expect(snapshot.hapticActionIDs == ["cycle_dpi", "play_pause"])
        #expect(snapshot.hapticButtonIDs == ["middle", "gesture"])
        #expect(!snapshot.hapticDedup)
        #expect(snapshot.appearanceMode == .dark)
        #expect(snapshot.debugMode)
        #expect(snapshot.deviceLayoutOverrides == ["mx_master_modern": "mx_vertical"])
        #expect(snapshot.language == .traditionalChinese)
        #expect(!snapshot.startMinimized)
        #expect(!snapshot.startAtLogin)
        #expect(!snapshot.checkForUpdates)
        #expect(snapshot.screenshotDirectory == "/tmp/Mouser Screenshots")
        #expect(snapshot.wheelInversionBackend == .macOS)
        #expect(snapshot.gestureThreshold == 32)
        #expect(snapshot.gestureCommitWindowMilliseconds == 450)
        #expect(snapshot.gestureSettleMilliseconds == 110)
        #expect(snapshot.gestureCrossRatio == 0.6)
        #expect(snapshot.horizontalScrollThreshold == 0.2)
        #expect(snapshot.actionsRingHoldMilliseconds == 320)
        #expect(!snapshot.actionsRingHoverHaptic)
        #expect(!snapshot.actionsRingUsesGlobalSlots)
        #expect(snapshot.actionsRingGlobalSlots == [
            "mission_control", "play_pause", "show_desktop", "launchpad",
        ])
        #expect(snapshot.profiles.count == 2)
        #expect(snapshot.profiles.first(where: { $0.id == "finder" })?.mappings.first(where: { $0.button == .back })?.action == .paste)
        let finder = try #require(snapshot.profiles.first(where: { $0.id == "finder" }))
        #expect(finder.mappingValue(for: "gesture") == "gesture_swipe")
        #expect(finder.mappingValue(for: "gesture_tap") == "app_expose")
        #expect(finder.mappingValue(for: "gesture_left") == "space_left")
        #expect(finder.mappingValue(for: "hscroll_left") == "space_left")
        #expect(finder.actionsRingSlots == ["copy", "paste", "mission_control", "show_desktop"])
    }

    @Test("startup settings use safe defaults when absent")
    func startupSettingsUseSafeDefaults() throws {
        let root = try JSONDecoder().decode(
            JSONValue.self,
            from: Data("{\"version\":11,\"profiles\":{},\"settings\":{}}".utf8)
        )

        let snapshot = try MouserConfigurationSnapshot(root: root)

        #expect(!snapshot.startMinimized)
        #expect(!snapshot.startAtLogin)
        #expect(snapshot.checkForUpdates)
        #expect(!snapshot.debugMode)
        #expect(snapshot.dpiPresets == [800, 1200, 1600, 2400])
        #expect(snapshot.screenshotDirectory.isEmpty)
        #expect(snapshot.wheelInversionBackend == .automatic)
        #expect(snapshot.language == .english)
    }

    @Test("successful retry clears only its keyed save failure")
    func successfulRetryClearsOnlyItsFailure() {
        var tracker = ConfigurationWriteStateTracker()
        let firstA = tracker.begin(key: "setting.a")
        let firstB = tracker.begin(key: "setting.b")

        let finishedFirstA = tracker.finish(key: "setting.a", generation: firstA, error: "A failed")
        let finishedFirstB = tracker.finish(key: "setting.b", generation: firstB, error: "B failed")
        #expect(finishedFirstA)
        #expect(finishedFirstB)
        #expect(tracker.failureMessage == "A failed")

        let retryA = tracker.begin(key: "setting.a")
        #expect(tracker.isSaving)
        let finishedRetryA = tracker.finish(key: "setting.a", generation: retryA)
        #expect(finishedRetryA)
        #expect(!tracker.isSaving)
        #expect(tracker.failureMessage == "B failed")

        let retryB = tracker.begin(key: "setting.b")
        let finishedRetryB = tracker.finish(key: "setting.b", generation: retryB)
        #expect(finishedRetryB)
        #expect(tracker.failureMessage == nil)
    }

    @Test("stale save completion cannot restore an older generation error")
    func staleSaveCompletionIsIgnored() {
        var tracker = ConfigurationWriteStateTracker()
        let stale = tracker.begin(key: "setting.dpi")
        let latest = tracker.begin(key: "setting.dpi")

        let finishedStale = tracker.finish(key: "setting.dpi", generation: stale, error: "stale")
        let finishedLatest = tracker.finish(key: "setting.dpi", generation: latest)
        #expect(!finishedStale)
        #expect(finishedLatest)
        #expect(!tracker.isSaving)
        #expect(tracker.failureMessage == nil)
    }

    @Test("first load creates a secure default configuration and visible startup")
    @MainActor
    func firstLoadCreatesSecureDefaults() async throws {
        let fixture = try TemporaryConfigFixture()
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        let result = try await store.loadWithDisposition()

        #expect(result.disposition == .created)
        #expect(result.snapshot.activeProfileID == "default")
        #expect(!result.snapshot.startMinimized)
        #expect(result.snapshot.gestureThreshold == 25)
        #expect(result.snapshot.profiles.map(\.id) == ["default"])
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path(percentEncoded: false)))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path(percentEncoded: false)
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let firstRunFixture = try TemporaryConfigFixture()
        let model = WorkspaceModel.live(
            configStore: MouserConfigStore(fileURL: firstRunFixture.fileURL),
            accessibilityAuthorizer: ConfigTestAccessibilityAuthorizer()
        )
        await model.loadConfiguration()
        #expect(model.configurationLoaded)
        #expect(!model.shouldStartMinimizedAfterBootstrap)
        #expect(model.shouldPresentSettingsAfterBootstrap)
        #expect(model.configurationPersistenceState == .saved("已创建默认配置"))
    }

    @Test("corrupt configuration is secured as a backup before defaults replace it")
    func corruptConfigurationIsBackedUpBeforeRecovery() async throws {
        let fixture = try TemporaryConfigFixture(json: "{ definitely-not-json")
        let original = try Data(contentsOf: fixture.fileURL)
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        let result = try await store.loadWithDisposition()

        guard case let .recovered(backupFileName) = result.disposition else {
            Issue.record("Expected corrupt configuration recovery")
            return
        }
        let backupURL = fixture.directoryURL.appending(path: backupFileName)
        #expect(try Data(contentsOf: backupURL) == original)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: backupURL.path(percentEncoded: false)
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #expect(!result.snapshot.startMinimized)
        #expect(try await store.loadWithDisposition().disposition == .existing)
    }

    @Test("structurally invalid writable containers use the same recovery path")
    func structurallyInvalidConfigurationIsRecovered() async throws {
        let fixture = try TemporaryConfigFixture(
            json: "{\"version\":11,\"profiles\":{},\"settings\":[]}"
        )
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        let result = try await store.loadWithDisposition()

        guard case let .recovered(backupFileName) = result.disposition else {
            Issue.record("Expected structural configuration recovery")
            return
        }
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.directoryURL.appending(path: backupFileName).path(percentEncoded: false)
            )
        )
        #expect(result.snapshot.profiles.map(\.id) == ["default"])
    }

    @Test("only an existing explicit setting may minimize startup")
    @MainActor
    func explicitExistingSettingMayMinimizeStartup() async throws {
        let fixture = try TemporaryConfigFixture(
            json: existingConfigFixture.replacingOccurrences(
                of: "\"start_minimized\": false",
                with: "\"start_minimized\": true"
            )
        )
        let model = WorkspaceModel.live(
            configStore: MouserConfigStore(fileURL: fixture.fileURL),
            accessibilityAuthorizer: ConfigTestAccessibilityAuthorizer()
        )

        await model.loadConfiguration()

        #expect(model.startMinimized)
        #expect(model.shouldStartMinimizedAfterBootstrap)
        #expect(!model.shouldPresentSettingsAfterBootstrap)
    }

    @Test("loads an enabled login item setting")
    func loadsEnabledLoginItemSetting() throws {
        let root = try JSONDecoder().decode(
            JSONValue.self,
            from: Data("{\"version\":11,\"profiles\":{},\"settings\":{\"start_at_login\":true}}".utf8)
        )

        #expect(try MouserConfigurationSnapshot(root: root).startAtLogin)
    }

    @Test("native localization resources cover all supported languages")
    func localizationResourcesLoad() {
        #expect(AppLanguage.english.localized("概览") == "Overview")
        #expect(AppLanguage.simplifiedChinese.localized("概览") == "概览")
        #expect(AppLanguage.traditionalChinese.localized("概览") == "概覽")
        #expect(
            AppLanguage.english.formatted("当前设备支持 %@–%@ DPI。", "400", "8000") ==
                "This device supports 400–8000 DPI."
        )
        #expect(
            AppLanguage.english.localizedRuntime("已连接 · 接收器槽位 2") ==
                "Connected · Receiver Slot 2"
        )
        #expect(
            AppLanguage.traditionalChinese.localizedRuntime("安装失败：签名无效") ==
                "安裝失敗：簽章無效"
        )
        #expect(
            AppLanguage.english.localizedRuntime("上次更新失败：签名无效") ==
                "Previous Update Failed: Invalid Signature"
        )
        #expect(
            AppLanguage.traditionalChinese.localizedRuntime("上次更新失败：签名无效") ==
                "上次更新失敗：簽章無效"
        )
        #expect(
            AppLanguage.english.localizedRuntime(
                "写入临时配置失败（config.json）：磁盘已满"
            ) == "Failed to Write Temporary Configuration (config.json): 磁盘已满"
        )
        #expect(
            AppLanguage.english.localized("修改会自动保存到当前应用配置。") ==
                "Changes are saved automatically to the current app profile."
        )
        #expect(AppLanguage.english.localized("详细设置…") == "Detailed Settings…")
        #expect(AppLanguage.traditionalChinese.localized("详细设置…") == "詳細設定…")
        #expect(
            AppLanguage.english.localized(
                "Mouser 会验证摘要和发行者签名，然后替换应用并自动重新打开。"
            ) == "Mouser verifies the digest and publisher signature, then replaces the app and reopens it automatically."
        )
        #expect(
            AppLanguage.traditionalChinese.localized(
                "Mouser 会验证摘要和发行者签名，然后替换应用并自动重新打开。"
            ) == "Mouser 會驗證摘要與發行者簽章，然後取代應用程式並自動重新開啟。"
        )
    }

    @Test("English and Traditional Chinese localization tables stay in key parity")
    func localizationTablesStayInParity() throws {
        func table(_ localization: String) throws -> [String: String] {
            let path = try #require(
                Bundle.main.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: localization
                )
            )
            let propertyList = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: URL(filePath: path)),
                format: nil
            )
            return try #require(propertyList as? [String: String])
        }

        let english = try table("en")
        let traditionalChinese = try table("zh-Hant")

        #expect(english.count >= 380)
        #expect(Set(english.keys) == Set(traditionalChinese.keys))
    }

    @Test("updating one setting preserves unknown future fields")
    func preservesUnknownFields() async throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        try await store.update(.setting(key: "invert_vscroll", value: .bool(false)))

        let data = try Data(contentsOf: fixture.fileURL)
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(root.value(at: ["settings", "invert_vscroll"]) == .bool(false))
        #expect(root.value(at: ["settings", "future_setting", "mode"]) == .string("preserve-me"))
        #expect(root.value(at: ["future_root", "kept"]) == .bool(true))
        #expect(root.value(at: ["profiles", "finder", "future_profile_value"]) == .integer(42))
    }

    @Test("updating a mapping only changes the selected profile button")
    func updatesSelectedMapping() async throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        try await store.update(.mapping(profileID: "finder", buttonID: "xbutton1", actionID: "browser_back"))

        let snapshot = try await store.load()
        #expect(snapshot.profiles.first(where: { $0.id == "finder" })?.mappings.first(where: { $0.button == .back })?.action == .browserBack)
        #expect(snapshot.profiles.first(where: { $0.id == "default" })?.mappings.first(where: { $0.button == .back })?.action == .mouseBack)
    }

    @Test("creating and deleting an application profile preserves inherited mappings")
    func createsAndDeletesProfile() async throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        let store = MouserConfigStore(fileURL: fixture.fileURL)

        try await store.update(
            .createProfile(
                id: "safari",
                label: "Safari",
                appIdentifiers: ["com.apple.Safari", "/Applications/Safari.app"],
                copyFrom: "default"
            )
        )

        var snapshot = try await store.load()
        let safari = try #require(snapshot.profiles.first(where: { $0.id == "safari" }))
        #expect(safari.appIdentifiers == ["com.apple.Safari", "/Applications/Safari.app"])
        #expect(safari.mappingValue(for: "xbutton1") == "mouse_back_click")

        try await store.update(.activeProfile(id: "safari"))
        try await store.update(.deleteProfile(id: "safari"))

        snapshot = try await store.load()
        #expect(!snapshot.profiles.contains(where: { $0.id == "safari" }))
        #expect(snapshot.activeProfileID == "default")
    }

    @Test("live workspace loads and saves through the compatibility store")
    @MainActor
    func liveWorkspaceUsesCompatibilityStore() async throws {
        let fixture = try TemporaryConfigFixture(json: existingConfigFixture)
        let store = MouserConfigStore(fileURL: fixture.fileURL)
        let model = WorkspaceModel.live(
            configStore: store,
            accessibilityAuthorizer: ConfigTestAccessibilityAuthorizer()
        )

        await model.loadConfiguration()
        #expect(model.configurationLoaded)
        #expect(model.selectedProfileID == "finder")
        #expect(model.dpi == 1450)
        #expect(model.language == .traditionalChinese)

        model.dpi = 1750
        model.language = .english
        #expect(model.configurationPersistenceState == .saving)
        await model.flushPendingWrites()

        #expect(model.configurationPersistenceState == .saved("更改已保存"))

        let snapshot = try await store.load()
        #expect(snapshot.dpi == 1750)
        #expect(snapshot.language == .english)
    }

}

@MainActor
private final class ConfigTestAccessibilityAuthorizer: AccessibilityAuthorizing {
    func isTrusted(prompt: Bool) -> Bool { false }
}

private struct TemporaryConfigFixture {
    let directoryURL: URL
    let fileURL: URL

    init(json: String? = nil) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Mouser Native Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        fileURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let json {
            try Data(json.utf8).write(to: fileURL, options: .atomic)
        }
    }
}
