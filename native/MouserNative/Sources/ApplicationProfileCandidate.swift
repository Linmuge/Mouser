import Foundation

struct ApplicationProfileCandidate: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String?
    let applicationPath: String

    var appIdentifiers: [String] {
        var identifiers: [String] = []
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            identifiers.append(bundleIdentifier)
        }
        if !applicationPath.isEmpty {
            identifiers.append(applicationPath)
        }
        return identifiers
    }

    var systemImage: String {
        switch bundleIdentifier?.lowercased() {
        case "com.apple.finder": "face.smiling"
        case "com.apple.safari": "safari"
        default: "app"
        }
    }

    init(name: String, bundleIdentifier: String?, applicationPath: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
    }

    init?(applicationURL: URL) {
        guard applicationURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: applicationURL)
        else { return nil }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent
        self.init(
            name: displayName,
            bundleIdentifier: bundle.bundleIdentifier,
            applicationPath: applicationURL.standardizedFileURL.path(percentEncoded: false)
        )
    }
}
