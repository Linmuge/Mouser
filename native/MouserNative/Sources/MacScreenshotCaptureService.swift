import Foundation

protocol ScreenshotCapturing: Sendable {
    func capture(_ action: MouserAction, directoryURL: URL) async throws -> URL
}

enum ScreenshotCaptureError: LocalizedError {
    case unsupportedAction(String)
    case commandFailed(Int32)
    case outputMissing(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAction(actionID):
            "不支持的截图动作：\(actionID)"
        case let .commandFailed(status):
            status == 1 ? "截图已取消" : "截图失败（screencapture 退出码 \(status)）"
        case let .outputMissing(url):
            "截图未保存到 \(url.path(percentEncoded: false))"
        }
    }
}

enum ScreenshotFilePlanner {
    static func nextTargetURL(
        directory: URL,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stamp = formatter.string(from: now)

        for index in 1...9_999 {
            let name = index == 1
                ? "Screenshot \(stamp).png"
                : "Screenshot \(stamp) (\(index)).png"
            let candidate = directory.appending(path: name, directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

actor MacScreenshotCaptureService: ScreenshotCapturing {
    private let executableURL = URL(filePath: "/usr/sbin/screencapture")

    static func arguments(for action: MouserAction, targetURL: URL) -> [String]? {
        switch action {
        case .screenshotRegionFile:
            ["-i", targetURL.path(percentEncoded: false)]
        case .screenshotFullFile:
            [targetURL.path(percentEncoded: false)]
        default:
            nil
        }
    }

    func capture(_ action: MouserAction, directoryURL: URL) async throws -> URL {
        let targetURL = try ScreenshotFilePlanner.nextTargetURL(directory: directoryURL)
        guard let arguments = Self.arguments(for: action, targetURL: targetURL) else {
            throw ScreenshotCaptureError.unsupportedAction(action.rawValue)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ScreenshotCaptureError.commandFailed(process.terminationStatus)
        }
        guard FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
            throw ScreenshotCaptureError.outputMissing(targetURL)
        }
        return targetURL
    }
}
