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

    @Test("startup settings retain Python defaults when absent")
    func startupSettingsUsePythonDefaults() throws {
        let root = try JSONDecoder().decode(
            JSONValue.self,
            from: Data("{\"version\":11,\"profiles\":{},\"settings\":{}}".utf8)
        )

        let snapshot = try MouserConfigurationSnapshot(root: root)

        #expect(snapshot.startMinimized)
        #expect(!snapshot.startAtLogin)
        #expect(snapshot.checkForUpdates)
        #expect(!snapshot.debugMode)
        #expect(snapshot.dpiPresets == [800, 1200, 1600, 2400])
        #expect(snapshot.screenshotDirectory.isEmpty)
        #expect(snapshot.wheelInversionBackend == .automatic)
        #expect(snapshot.language == .english)
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
            AppLanguage.english.localizedRuntime(
                "写入临时配置失败（config.json）：磁盘已满"
            ) == "Failed to Write Temporary Configuration (config.json): 磁盘已满"
        )
        #expect(
            AppLanguage.english.localized("修改会自动保存到当前应用配置。") ==
                "Changes are saved automatically to the current app profile."
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
        await model.flushPendingWrites()

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

    init(json: String) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Mouser Native Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        fileURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL, options: .atomic)
    }
}
