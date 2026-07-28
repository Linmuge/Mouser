import Foundation
import Testing
@testable import MouserNative

@Suite("macOS screenshot file capture")
struct MacScreenshotCaptureTests {
    @Test("allocates Python-compatible names and skips collisions")
    func allocatesCompatibleNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-06-10T14:09:23Z")
        )
        let first = directory.appending(path: "Screenshot 2026-06-10 140923.png")
        let second = directory.appending(path: "Screenshot 2026-06-10 140923 (2).png")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: second.path, contents: Data())

        let target = try ScreenshotFilePlanner.nextTargetURL(
            directory: directory,
            now: date,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(target.lastPathComponent == "Screenshot 2026-06-10 140923 (3).png")
    }

    @Test("builds interactive and full-screen screencapture arguments")
    func buildsCaptureArguments() {
        let target = URL(filePath: "/tmp/Screenshot.png")

        #expect(
            MacScreenshotCaptureService.arguments(
                for: .screenshotRegionFile,
                targetURL: target
            ) == ["-i", target.path]
        )
        #expect(
            MacScreenshotCaptureService.arguments(
                for: .screenshotFullFile,
                targetURL: target
            ) == [target.path]
        )
    }
}
