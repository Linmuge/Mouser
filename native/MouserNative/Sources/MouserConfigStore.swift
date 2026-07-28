import Darwin
import Foundation

enum SecureAtomicFileWriterError: LocalizedError {
    case temporaryWrite(URL, String)
    case temporaryPermissions(URL, String)
    case temporarySync(URL, String)
    case invalidFileSystemPath(URL)

    var errorDescription: String? {
        switch self {
        case let .temporaryWrite(url, message):
            "写入临时配置失败（\(url.lastPathComponent)）：\(message)"
        case let .temporaryPermissions(url, message):
            "设置临时配置权限失败（\(url.lastPathComponent)）：\(message)"
        case let .temporarySync(url, message):
            "同步临时配置失败（\(url.lastPathComponent)）：\(message)"
        case let .invalidFileSystemPath(url):
            "配置路径无效：\(url.path(percentEncoded: false))"
        }
    }
}

struct SecureAtomicFileWriter: Sendable {
    func write(_ data: Data, to fileURL: URL) throws {
        let temporaryURL = fileURL.deletingLastPathComponent().appending(
            path: "\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        do {
            try data.write(to: temporaryURL, options: .withoutOverwriting)
        } catch {
            throw SecureAtomicFileWriterError.temporaryWrite(
                temporaryURL,
                error.localizedDescription
            )
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path(percentEncoded: false)
            )
        } catch {
            throw SecureAtomicFileWriterError.temporaryPermissions(
                temporaryURL,
                error.localizedDescription
            )
        }
        do {
            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw SecureAtomicFileWriterError.temporarySync(
                temporaryURL,
                error.localizedDescription
            )
        }

        var invalidPath = false
        let renameResult: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { sourcePath in
            fileURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    invalidPath = true
                    return Int32(-1)
                }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            if invalidPath {
                throw SecureAtomicFileWriterError.invalidFileSystemPath(fileURL)
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func value(at path: [String]) -> JSONValue? {
        guard let key = path.first else { return self }
        guard case let .object(object) = self, let child = object[key] else { return nil }
        return child.value(at: Array(path.dropFirst()))
    }

    mutating func setValue(_ value: JSONValue, at path: [String]) throws {
        guard let key = path.first else {
            self = value
            return
        }
        guard case var .object(object) = self else {
            throw MouserConfigError.expectedObject(path: path)
        }
        if path.count == 1 {
            object[key] = value
        } else {
            var child = object[key] ?? .object([:])
            try child.setValue(value, at: Array(path.dropFirst()))
            object[key] = child
        }
        self = .object(object)
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        switch self {
        case let .integer(value): value
        case let .number(value): Int(value)
        default: nil
        }
    }

    var numberValue: Double? {
        switch self {
        case let .integer(value): Double(value)
        case let .number(value): value
        default: nil
        }
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }
}

enum MouserConfigMutation: Equatable, Sendable {
    case setting(key: String, value: JSONValue)
    case activeProfile(id: String)
    case mapping(profileID: String, buttonID: String, actionID: String)
    case profileRingSlots(profileID: String, slots: [String])
    case createProfile(id: String, label: String, appIdentifiers: [String], copyFrom: String)
    case deleteProfile(id: String)

    func apply(to root: inout JSONValue) throws {
        switch self {
        case let .setting(key, value):
            try root.setValue(value, at: ["settings", key])
        case let .activeProfile(id):
            try root.setValue(.string(id), at: ["active_profile"])
        case let .mapping(profileID, buttonID, actionID):
            try root.setValue(
                .string(actionID),
                at: ["profiles", profileID, "mappings", buttonID]
            )
        case let .profileRingSlots(profileID, slots):
            try root.setValue(
                .array(slots.map(JSONValue.string)),
                at: ["profiles", profileID, "mappings", "actions_ring_slots"]
            )
        case let .createProfile(id, label, appIdentifiers, copyFrom):
            let source = root.value(at: ["profiles", copyFrom])?.objectValue
                ?? root.value(at: ["profiles", "default"])?.objectValue
                ?? [:]
            var profile: [String: JSONValue] = [
                "label": .string(label),
                "apps": .array(appIdentifiers.map(JSONValue.string)),
                "mappings": source["mappings"] ?? .object([:]),
            ]
            if let buttonHaptic = source["button_haptic"] {
                profile["button_haptic"] = buttonHaptic
            }
            try root.setValue(.object(profile), at: ["profiles", id])
        case let .deleteProfile(id):
            guard id != "default", case var .object(rootObject) = root,
                  case var .object(profiles) = rootObject["profiles"]
            else { return }
            profiles.removeValue(forKey: id)
            rootObject["profiles"] = .object(profiles)
            if rootObject["active_profile"]?.stringValue == id {
                rootObject["active_profile"] = .string("default")
            }
            root = .object(rootObject)
        }
    }
}

enum MouserConfigError: Error, Equatable {
    case expectedObject(path: [String])
    case invalidRoot
}

struct MouserConfigurationSnapshot: Equatable, Sendable {
    let version: Int
    let activeProfileID: String
    let dpi: Int
    let dpiPresets: [Int]
    let smartShiftEnabled: Bool
    let smartShiftMode: SmartShiftMode
    let smartShiftThreshold: Int
    let scrollForce: Int
    let invertVerticalScroll: Bool
    let invertHorizontalScroll: Bool
    let wheelInversionBackend: WheelInversionBackend
    let ignoreTrackpad: Bool
    let hapticsEnabled: Bool
    let hapticLevel: Int
    let hapticActionIDs: [String]
    let hapticButtonIDs: [String]
    let hapticDedup: Bool
    let appearanceMode: AppearanceMode
    let language: AppLanguage
    let debugMode: Bool
    let deviceLayoutOverrides: [String: String]
    let startMinimized: Bool
    let startAtLogin: Bool
    let checkForUpdates: Bool
    let screenshotDirectory: String
    let gestureThreshold: Double
    let gestureCommitWindowMilliseconds: Double
    let gestureSettleMilliseconds: Double
    let gestureCrossRatio: Double
    let horizontalScrollThreshold: Double
    let actionsRingHoldMilliseconds: Int
    let actionsRingHoverHaptic: Bool
    let actionsRingUsesGlobalSlots: Bool
    let actionsRingGlobalSlots: [String]
    let forceSensitivity: Int?
    let profiles: [AppProfile]

    init(root: JSONValue) throws {
        guard root.objectValue != nil else { throw MouserConfigError.invalidRoot }
        version = root.value(at: ["version"])?.integerValue ?? 11
        activeProfileID = root.value(at: ["active_profile"])?.stringValue ?? "default"
        dpi = root.value(at: ["settings", "dpi"])?.integerValue ?? 1000
        let decodedDPIPresets = root.value(at: ["settings", "dpi_presets"])?
            .arrayValue?.compactMap(\.integerValue) ?? []
        dpiPresets = decodedDPIPresets.isEmpty
            ? [800, 1200, 1600, 2400]
            : decodedDPIPresets.map { min(8_000, max(200, $0)) }
        smartShiftEnabled = root.value(at: ["settings", "smart_shift_enabled"])?.boolValue ?? false
        smartShiftMode = SmartShiftMode(
            rawValue: root.value(at: ["settings", "smart_shift_mode"])?.stringValue ?? "ratchet"
        ) ?? .ratchet
        smartShiftThreshold = root.value(at: ["settings", "smart_shift_threshold"])?.integerValue ?? 25
        scrollForce = root.value(at: ["settings", "scroll_force"])?.integerValue ?? 50
        invertVerticalScroll = root.value(at: ["settings", "invert_vscroll"])?.boolValue ?? false
        invertHorizontalScroll = root.value(at: ["settings", "invert_hscroll"])?.boolValue ?? false
        wheelInversionBackend = WheelInversionBackend(
            rawValue: root.value(at: ["settings", "wheel_divert"])?.stringValue ?? "auto"
        ) ?? .automatic
        ignoreTrackpad = root.value(at: ["settings", "ignore_trackpad"])?.boolValue ?? true
        hapticsEnabled = root.value(at: ["settings", "haptic_enabled"])?.boolValue ?? true
        hapticLevel = root.value(at: ["settings", "haptic_level"])?.integerValue ?? 2
        hapticActionIDs = root.value(at: ["settings", "action_haptic"])?
            .arrayValue?.compactMap(\.stringValue) ?? []
        hapticButtonIDs = root.value(at: ["settings", "button_haptic"])?
            .arrayValue?.compactMap(\.stringValue) ?? []
        hapticDedup = root.value(at: ["settings", "haptic_dedup"])?.boolValue ?? true
        appearanceMode = AppearanceMode(
            rawValue: root.value(at: ["settings", "appearance_mode"])?.stringValue ?? "system"
        ) ?? .system
        language = AppLanguage(
            rawValue: root.value(at: ["settings", "language"])?.stringValue ?? "en"
        ) ?? .english
        debugMode = root.value(at: ["settings", "debug_mode"])?.boolValue ?? false
        deviceLayoutOverrides = root.value(at: ["settings", "device_layout_overrides"])?.objectValue?
            .compactMapValues(\.stringValue) ?? [:]
        startMinimized = root.value(at: ["settings", "start_minimized"])?.boolValue ?? true
        startAtLogin = root.value(at: ["settings", "start_at_login"])?.boolValue ?? false
        checkForUpdates = root.value(at: ["settings", "check_for_updates"])?.boolValue ?? true
        screenshotDirectory = root.value(
            at: ["settings", "screenshot_directory"]
        )?.stringValue ?? ""
        gestureThreshold = root.value(at: ["settings", "gesture_threshold"])?.numberValue ?? 50
        gestureCommitWindowMilliseconds = root.value(
            at: ["settings", "gesture_commit_window_ms"]
        )?.numberValue ?? 400
        gestureSettleMilliseconds = root.value(
            at: ["settings", "gesture_settle_ms"]
        )?.numberValue ?? 90
        gestureCrossRatio = root.value(at: ["settings", "gesture_cross_ratio"])?.numberValue ?? 0.5
        horizontalScrollThreshold = max(
            0.01,
            root.value(at: ["settings", "hscroll_threshold"])?.numberValue ?? 0.1
        )
        actionsRingHoldMilliseconds = min(
            500,
            max(100, root.value(at: ["settings", "actions_ring_hold_ms"])?.integerValue ?? 250)
        )
        actionsRingHoverHaptic = root.value(
            at: ["settings", "actions_ring_hover_haptic"]
        )?.boolValue ?? true
        actionsRingUsesGlobalSlots = root.value(
            at: ["settings", "actions_ring_use_global"]
        )?.boolValue ?? true
        actionsRingGlobalSlots = root.value(at: ["settings", "actions_ring_slots"])?
            .arrayValue?.compactMap(\.stringValue) ?? [
                "mission_control", "play_pause", "show_desktop", "launchpad",
            ]
        forceSensitivity = root.value(at: ["settings", "force_sensitivity"])?.integerValue
        profiles = Self.decodeProfiles(root.value(at: ["profiles"])?.objectValue ?? [:])
    }

    private static func decodeProfiles(_ profilesObject: [String: JSONValue]) -> [AppProfile] {
        profilesObject.map { id, value in
            let object = value.objectValue ?? [:]
            let rawLabel = object["label"]?.stringValue ?? id
            let apps = object["apps"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let mappingsObject = object["mappings"]?.objectValue ?? [:]
            let mappings = MouseButton.allCases.map { button in
                ButtonMapping(
                    button: button,
                    actionID: mappingsObject[button.configID]?.stringValue ?? MouserAction.passThrough.rawValue
                )
            }
            let physicalKeys = Set(MouseButton.allCases.map(\.configID))
            let supplementalMappings = mappingsObject.reduce(into: [String: String]()) {
                result, item in
                guard !physicalKeys.contains(item.key), let actionID = item.value.stringValue else {
                    return
                }
                result[item.key] = actionID
            }
            let actionsRingSlots = mappingsObject["actions_ring_slots"]?
                .arrayValue?.compactMap(\.stringValue) ?? []
            return AppProfile(
                id: id,
                name: id == "default" ? "默认" : rawLabel,
                bundleID: apps.first,
                systemImage: systemImage(for: apps.first),
                mappings: mappings,
                supplementalMappings: supplementalMappings,
                actionsRingSlots: actionsRingSlots,
                appIdentifiers: apps
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == "default" { return true }
            if rhs.id == "default" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func systemImage(for bundleID: String?) -> String {
        guard let bundleID else { return "square.grid.2x2" }
        if bundleID == "com.apple.finder" { return "face.smiling" }
        if bundleID == "com.apple.Safari" { return "safari" }
        return "app"
    }
}

actor MouserConfigStore {
    static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Mouser", directoryHint: .isDirectory)
        .appending(path: "config.json", directoryHint: .notDirectory)

    private let fileURL: URL
    private let fileWriter = SecureAtomicFileWriter()
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(fileURL: URL = MouserConfigStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> MouserConfigurationSnapshot {
        let root = try readRoot()
        return try MouserConfigurationSnapshot(root: root)
    }

    func update(_ mutation: MouserConfigMutation) throws {
        var root = try readRoot()
        try mutation.apply(to: &root)
        try write(root)
    }

    private func readRoot() throws -> JSONValue {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(JSONValue.self, from: data)
    }

    private func write(_ root: JSONValue) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encoder.encode(root)
        try fileWriter.write(data, to: fileURL)
    }
}
