import Foundation

struct LogitechDeviceProfile: Equatable, Sendable {
    let key: String
    let dpiRange: ClosedRange<Double>
    let imageResource: String?
}

struct LogitechDeviceLayoutChoice: Identifiable, Equatable, Sendable {
    let key: String
    let title: String
    var id: String { key }
}

enum LogitechDeviceCatalog {
    static let generic = LogitechDeviceProfile(
        key: "generic",
        dpiRange: 200...8_000,
        imageResource: nil
    )

    static let manualLayoutChoices = [
        LogitechDeviceLayoutChoice(key: "", title: "自动检测"),
        LogitechDeviceLayoutChoice(key: "mx_master", title: "MX Master"),
        LogitechDeviceLayoutChoice(key: "mx_anywhere", title: "MX Anywhere"),
        LogitechDeviceLayoutChoice(key: "mx_vertical", title: "MX Vertical"),
    ]

    static func profile(layoutKey: String) -> LogitechDeviceProfile? {
        switch layoutKey {
        case "mx_master":
            .init(key: layoutKey, dpiRange: 200...8_000, imageResource: "mx-master-3s")
        case "mx_anywhere":
            .init(key: layoutKey, dpiRange: 200...8_000, imageResource: "mouse_mx_anywhere_3s")
        case "mx_vertical":
            .init(key: layoutKey, dpiRange: 200...4_000, imageResource: "mx_vertical")
        default:
            nil
        }
    }

    static func profile(named rawName: String) -> LogitechDeviceProfile {
        let name = rawName.lowercased()
        if name.contains("g502 x") {
            return .init(key: "g502_x", dpiRange: 100...25_600, imageResource: nil)
        }
        if name.contains("g502") {
            return .init(key: "g502", dpiRange: 200...12_000, imageResource: nil)
        }
        if name.contains("vertical") {
            return .init(key: "mx_vertical", dpiRange: 200...4_000, imageResource: "mx_vertical")
        }
        if name.contains("anywhere 3s") {
            return .init(key: "mx_anywhere_3s", dpiRange: 200...8_000, imageResource: "mouse_mx_anywhere_3s")
        }
        if name.contains("anywhere") {
            return .init(key: "mx_anywhere", dpiRange: 200...4_000, imageResource: "mouse_mx_anywhere_3s")
        }
        if name.contains("master 4") || name.contains("master 3s") {
            return .init(key: "mx_master_modern", dpiRange: 200...8_000, imageResource: "mx-master-3s")
        }
        if name.contains("master") {
            return .init(key: "mx_master", dpiRange: 200...4_000, imageResource: "mx-master-3s")
        }
        if name.contains("m650") || name.contains("signature m650") {
            return .init(key: "m650", dpiRange: 200...4_000, imageResource: nil)
        }
        if name.contains("m585") || name.contains("m590") {
            return .init(key: "m590", dpiRange: 200...8_000, imageResource: nil)
        }
        return generic
    }
}
