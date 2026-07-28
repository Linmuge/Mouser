import Foundation
import Testing
@testable import MouserNative

@MainActor
private final class FakeLoginItemController: LoginItemControlling {
    var isEnabled: Bool
    var error: (any Error)?
    private(set) var requestedStates: [Bool] = []

    init(isEnabled: Bool = false, error: (any Error)? = nil) {
        self.isEnabled = isEnabled
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedStates.append(enabled)
        if let error { throw error }
        isEnabled = enabled
    }
}

private struct LoginItemTestError: LocalizedError {
    var errorDescription: String? { "registration failed" }
}

@Suite("Login item lifecycle")
@MainActor
struct LoginItemControllerTests {
    @Test("successful changes update the model and configuration")
    func successfulChangePersists() async throws {
        let fixture = try LoginItemConfigFixture()
        let controller = FakeLoginItemController()
        let model = WorkspaceModel.live(
            configStore: fixture.store,
            accessibilityAuthorizer: LoginItemTestAuthorizer(),
            loginItemController: controller
        )
        await model.loadConfiguration()

        model.setStartAtLogin(true)
        await model.flushPendingWrites()

        #expect(controller.requestedStates == [true])
        #expect(model.startAtLogin)
        #expect(model.loginItemStatusText == "已启用")
        #expect(try await fixture.store.load().startAtLogin)
    }

    @Test("registration failure leaves the model and configuration disabled")
    func failedChangeRollsBack() async throws {
        let fixture = try LoginItemConfigFixture()
        let controller = FakeLoginItemController(error: LoginItemTestError())
        let model = WorkspaceModel.live(
            configStore: fixture.store,
            accessibilityAuthorizer: LoginItemTestAuthorizer(),
            loginItemController: controller
        )
        await model.loadConfiguration()

        model.setStartAtLogin(true)
        await model.flushPendingWrites()

        #expect(controller.requestedStates == [true])
        #expect(!model.startAtLogin)
        #expect(model.loginItemStatusText.contains("registration failed"))
        #expect(!(try await fixture.store.load().startAtLogin))
    }
}

@MainActor
private final class LoginItemTestAuthorizer: AccessibilityAuthorizing {
    func isTrusted(prompt: Bool) -> Bool { true }
}

private struct LoginItemConfigFixture {
    let directoryURL: URL
    let store: MouserConfigStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Mouser Login Item Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
        let json = """
        {
          "version": 11,
          "active_profile": "default",
          "profiles": {
            "default": {"label": "Default", "apps": [], "mappings": {}}
          },
          "settings": {"start_minimized": true, "start_at_login": false}
        }
        """
        try Data(json.utf8).write(to: fileURL)
        store = MouserConfigStore(fileURL: fileURL)
    }
}
