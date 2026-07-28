import AppKit
import CryptoKit
import Darwin
import Foundation

struct NativeUpdateInstallPlan: Codable, Equatable, Sendable {
    var parentProcessID: Int32
    var stagedAppPath: String
    var installAppPath: String
    var backupAppPath: String
    var expectedBundleIdentifier: String
    var expectedVersion: String

    func validatePaths() throws {
        guard parentProcessID > 1 else { throw UpdateInstallError.unsafeInstallPlan }
        let install = URL(filePath: installAppPath, directoryHint: .isDirectory).standardizedFileURL
        let staged = URL(filePath: stagedAppPath, directoryHint: .isDirectory).standardizedFileURL
        let backup = URL(filePath: backupAppPath, directoryHint: .isDirectory).standardizedFileURL
        let parent = install.deletingLastPathComponent()
        let stagingDirectory = staged.deletingLastPathComponent()
        guard install.pathExtension == "app",
              staged.pathExtension == "app",
              backup.pathExtension == "app",
              stagingDirectory.deletingLastPathComponent() == parent,
              stagingDirectory.lastPathComponent.hasPrefix(".\(install.lastPathComponent).update-"),
              backup.deletingLastPathComponent() == parent,
              backup.lastPathComponent.hasPrefix(".\(install.deletingPathExtension().lastPathComponent).backup-"),
              !expectedBundleIdentifier.isEmpty,
              !expectedVersion.isEmpty
        else {
            throw UpdateInstallError.unsafeInstallPlan
        }
    }
}

struct DiskImageAttachment: Equatable, Sendable {
    let mountURL: URL
    let wholeDiskIdentifier: String

    init(plistData: Data) throws {
        guard let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            format: nil
        ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first,
              let wholeDiskIdentifier = entities.compactMap({ entity -> String? in
                  guard let value = entity["dev-entry"] as? String else { return nil }
                  let identifier = URL(filePath: value).lastPathComponent
                  let suffix = identifier.dropFirst("disk".count)
                  guard identifier.hasPrefix("disk"),
                        !suffix.isEmpty,
                        suffix.allSatisfy(\.isNumber)
                  else { return nil }
                  return identifier
              }).first
        else { throw UpdateInstallError.invalidDiskImage }

        mountURL = URL(filePath: mountPath, directoryHint: .isDirectory)
        self.wholeDiskIdentifier = wholeDiskIdentifier
    }

    static func attachArguments(for diskImageURL: URL) -> [String] {
        [
            "image", "attach", "--readOnly", "--nobrowse", "--plist",
            diskImageURL.path(percentEncoded: false),
        ]
    }

    var ejectArguments: [String] { ["eject", wholeDiskIdentifier] }
}

protocol NativeUpdatePreparing: Sendable {
    func prepare(
        release: MouserRelease,
        currentAppURL: URL,
        parentProcessID: Int32
    ) async throws -> NativeUpdateInstallPlan
}

actor MacNativeUpdateInstaller: NativeUpdatePreparing {
    private let expectedBundleIdentifier = "io.github.tombadash.mouser"

    func prepare(
        release: MouserRelease,
        currentAppURL: URL,
        parentProcessID: Int32
    ) async throws -> NativeUpdateInstallPlan {
        guard let asset = release.installAsset, let expectedSHA256 = asset.sha256 else {
            throw UpdateInstallError.noVerifiedDMG
        }
        let currentAppURL = currentAppURL.standardizedFileURL
        guard currentAppURL.pathExtension == "app",
              Bundle(url: currentAppURL)?.bundleIdentifier == expectedBundleIdentifier
        else {
            throw UpdateInstallError.unsupportedInstall(
                "当前不是正式安装的 Mouser.app，请从 Release 页面手动安装"
            )
        }
        let installParent = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(
            atPath: installParent.path(percentEncoded: false)
        ) else {
            throw UpdateInstallError.unsupportedInstall(
                "Mouser 所在目录不可写，请从 Release 页面手动安装"
            )
        }

        let downloadURL = try await download(
            asset,
            expectedSHA256: expectedSHA256,
            version: release.version
        )
        try run("/usr/bin/hdiutil", ["verify", downloadURL.path(percentEncoded: false)])
        let attachment = try attach(downloadURL)
        defer { _ = try? run("/usr/sbin/diskutil", attachment.ejectArguments) }

        let candidateURL = try findApplication(in: attachment.mountURL)
        try validateApplication(candidateURL, expectedVersion: release.version)
        try run("/usr/bin/codesign", [
            "--verify", "--deep", "--strict", "--verbose=2",
            candidateURL.path(percentEncoded: false),
        ])
        try run("/usr/sbin/spctl", [
            "--assess", "--type", "execute", "--verbose=2",
            candidateURL.path(percentEncoded: false),
        ])

        let token = UUID().uuidString
        let stagingDirectory = installParent.appending(
            path: ".\(currentAppURL.lastPathComponent).update-\(token)",
            directoryHint: .isDirectory
        )
        let stagedAppURL = stagingDirectory.appending(
            path: currentAppURL.lastPathComponent,
            directoryHint: .isDirectory
        )
        let backupAppURL = installParent.appending(
            path: ".\(currentAppURL.deletingPathExtension().lastPathComponent).backup-\(token).app",
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: false
            )
            try run("/usr/bin/ditto", [
                candidateURL.path(percentEncoded: false),
                stagedAppURL.path(percentEncoded: false),
            ])
            try validateApplication(stagedAppURL, expectedVersion: release.version)
            try run("/usr/bin/codesign", [
                "--verify", "--deep", "--strict",
                stagedAppURL.path(percentEncoded: false),
            ])
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw error
        }

        let plan = NativeUpdateInstallPlan(
            parentProcessID: parentProcessID,
            stagedAppPath: stagedAppURL.path(percentEncoded: false),
            installAppPath: currentAppURL.path(percentEncoded: false),
            backupAppPath: backupAppURL.path(percentEncoded: false),
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedVersion: release.version
        )
        try plan.validatePaths()
        return plan
    }

    private func download(
        _ asset: MouserReleaseAsset,
        expectedSHA256: String,
        version: String
    ) async throws -> URL {
        var request = URLRequest(url: asset.downloadURL)
        request.timeoutInterval = 120
        request.setValue("MouserNative/\(version)", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { throw GitHubReleaseError.invalidResponse }

        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == asset.size else { throw UpdateInstallError.sizeMismatch }
        guard try fileSHA256(temporaryURL) == expectedSHA256 else {
            throw UpdateInstallError.checksumMismatch
        }

        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Mouser/Updates", directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: asset.name, directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func attach(_ diskImageURL: URL) throws -> DiskImageAttachment {
        let data = try run(
            "/usr/sbin/diskutil",
            DiskImageAttachment.attachArguments(for: diskImageURL),
            capturesOutput: true
        )
        return try DiskImageAttachment(plistData: data)
    }

    private func findApplication(in mountURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateInstallError.invalidDiskImage
        }
        return app
    }

    private func validateApplication(_ url: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: url),
              bundle.bundleIdentifier == expectedBundleIdentifier
        else {
            throw UpdateInstallError.invalidApplication("更新包不是官方 Mouser 应用")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == expectedVersion else {
            throw UpdateInstallError.invalidApplication("更新包版本与 Release 不一致")
        }
    }

    @discardableResult
    private func run(
        _ executable: String,
        _ arguments: [String],
        capturesOutput: Bool = false
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if capturesOutput {
            process.standardOutput = output
        }
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw UpdateInstallError.commandFailed(
                detail.isEmpty
                    ? "更新校验命令失败（\(process.terminationStatus)）"
                    : detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return capturesOutput ? data : Data()
    }
}

enum MacUpdateInstallHelper {
    static let argument = "--mouser-install-update"
    static let resultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Mouser/native-update-result.json")

    static func launch(_ plan: NativeUpdateInstallPlan) throws {
        try plan.validatePaths()
        let planURL = resultURL.deletingLastPathComponent()
            .appending(path: "pending-native-update.json")
        try FileManager.default.createDirectory(
            at: planURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(plan).write(to: planURL, options: .atomic)
        guard let executableURL = Bundle.main.executableURL else {
            throw UpdateInstallError.unsupportedInstall("找不到 Mouser 更新助手")
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [argument, planURL.path(percentEncoded: false)]
        try process.run()
    }

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1)
        else { return false }
        do {
            let planURL = URL(filePath: arguments[index + 1], directoryHint: .notDirectory)
            let plan = try JSONDecoder().decode(
                NativeUpdateInstallPlan.self,
                from: Data(contentsOf: planURL)
            )
            try install(plan)
            try JSONEncoder().encode(plan).write(to: resultURL, options: .atomic)
            try? FileManager.default.removeItem(at: planURL)
            return true
        } catch {
            let message = Data(error.localizedDescription.utf8)
            try? message.write(to: resultURL, options: .atomic)
            return true
        }
    }

    static func cleanupCompletedInstall() {
        guard let data = try? Data(contentsOf: resultURL),
              let plan = try? JSONDecoder().decode(NativeUpdateInstallPlan.self, from: data),
              let bundle = Bundle(url: URL(filePath: plan.installAppPath)),
              bundle.bundleIdentifier == plan.expectedBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == plan.expectedVersion
        else { return }
        try? FileManager.default.removeItem(at: URL(filePath: plan.backupAppPath))
        try? FileManager.default.removeItem(
            at: URL(filePath: plan.stagedAppPath).deletingLastPathComponent()
        )
        try? FileManager.default.removeItem(at: resultURL)
    }

    private static func install(_ plan: NativeUpdateInstallPlan) throws {
        try plan.validatePaths()
        let deadline = Date().addingTimeInterval(30)
        while Darwin.kill(plan.parentProcessID, 0) == 0, Date() < deadline {
            usleep(100_000)
        }
        guard Darwin.kill(plan.parentProcessID, 0) != 0 else {
            throw UpdateInstallError.commandFailed("Mouser 未能退出，更新已取消")
        }

        let manager = FileManager.default
        let installURL = URL(filePath: plan.installAppPath, directoryHint: .isDirectory)
        let stagedURL = URL(filePath: plan.stagedAppPath, directoryHint: .isDirectory)
        let backupURL = URL(filePath: plan.backupAppPath, directoryHint: .isDirectory)
        guard Bundle(url: stagedURL)?.bundleIdentifier == plan.expectedBundleIdentifier else {
            throw UpdateInstallError.invalidApplication("暂存应用身份不匹配")
        }
        try manager.moveItem(at: installURL, to: backupURL)
        do {
            try manager.moveItem(at: stagedURL, to: installURL)
            let open = Process()
            open.executableURL = URL(filePath: "/usr/bin/open")
            open.arguments = [installURL.path(percentEncoded: false)]
            try open.run()
            open.waitUntilExit()
            guard open.terminationStatus == 0 else {
                throw UpdateInstallError.commandFailed("新版 Mouser 无法启动")
            }
        } catch {
            try? manager.removeItem(at: installURL)
            try? manager.moveItem(at: backupURL, to: installURL)
            if manager.fileExists(atPath: installURL.path(percentEncoded: false)) {
                let open = Process()
                open.executableURL = URL(filePath: "/usr/bin/open")
                open.arguments = [installURL.path(percentEncoded: false)]
                try? open.run()
            }
            throw error
        }
    }
}
