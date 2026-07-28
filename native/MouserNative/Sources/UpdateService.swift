import CryptoKit
import Foundation

struct MouserReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int
    let contentType: String
    let sha256: String?

    var isVerifiedDMG: Bool {
        name.lowercased().hasSuffix(".dmg") &&
            !name.lowercased().contains("debug") &&
            size > 0 &&
            sha256?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

struct MouserRelease: Equatable, Sendable {
    let version: String
    let name: String
    let notes: String
    let releaseURL: URL
    let isPrerelease: Bool
    var assets: [MouserReleaseAsset] = []

    var installAsset: MouserReleaseAsset? {
        assets.first(where: \.isVerifiedDMG)
    }
}

enum UpdateInstallError: LocalizedError {
    case sizeMismatch
    case checksumMismatch
    case noVerifiedDMG
    case unsafeInstallPlan
    case unsupportedInstall(String)
    case commandFailed(String)
    case invalidDiskImage
    case invalidApplication(String)

    var errorDescription: String? {
        switch self {
        case .sizeMismatch: "下载的更新文件大小不匹配"
        case .checksumMismatch: "下载的更新文件校验失败"
        case .noVerifiedDMG: "此版本没有可校验的 DMG"
        case .unsafeInstallPlan: "更新安装路径不安全"
        case let .unsupportedInstall(message): message
        case let .commandFailed(message): message
        case .invalidDiskImage: "DMG 中没有可安装的 Mouser.app"
        case let .invalidApplication(message): message
        }
    }
}

enum UpdateAssetVerifier {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(
        _ data: Data,
        expectedSize: Int,
        expectedSHA256: String
    ) throws {
        guard data.count == expectedSize else { throw UpdateInstallError.sizeMismatch }
        guard sha256(data) == expectedSHA256.lowercased() else {
            throw UpdateInstallError.checksumMismatch
        }
    }
}

enum GitHubReleaseError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case draftRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "GitHub 返回了无效的更新信息"
        case let .httpStatus(code): "检查更新失败（HTTP \(code)）"
        case .draftRelease: "最新版本仍是草稿"
        }
    }
}

enum GitHubReleaseDecoder {
    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL
        let name: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]?

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int
            let contentType: String
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
                case contentType = "content_type"
                case digest
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case name
            case body
            case draft
            case prerelease
            case assets
        }
    }

    static func decode(_ data: Data) throws -> MouserRelease {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft else { throw GitHubReleaseError.draftRelease }
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        return MouserRelease(
            version: version,
            name: payload.name ?? "Mouser \(version)",
            notes: payload.body ?? "",
            releaseURL: payload.htmlURL,
            isPrerelease: payload.prerelease,
            assets: (payload.assets ?? []).map { asset in
                let digest = asset.digest?.lowercased()
                let sha256 = digest?.hasPrefix("sha256:") == true
                    ? String(digest!.dropFirst("sha256:".count))
                    : nil
                return MouserReleaseAsset(
                    name: asset.name,
                    downloadURL: asset.browserDownloadURL,
                    size: asset.size,
                    contentType: asset.contentType,
                    sha256: sha256
                )
            }
        )
    }
}

enum SemanticVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = components(candidate)
        let currentParts = components(current)
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? version
        return core.split(separator: ".").map { component in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
    }
}

protocol ReleaseChecking: Sendable {
    func latestRelease() async throws -> MouserRelease
}

struct GitHubReleaseChecker: ReleaseChecking {
    static let defaultRepository = "Linmuge/Mouser"
    static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/\(defaultRepository)/releases/latest"
    )!

    func latestRelease() async throws -> MouserRelease {
        var request = URLRequest(url: Self.latestReleaseEndpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "3.8.1"
        request.setValue("Mouser/\(version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubReleaseError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubReleaseError.httpStatus(response.statusCode)
        }
        return try GitHubReleaseDecoder.decode(data)
    }
}
