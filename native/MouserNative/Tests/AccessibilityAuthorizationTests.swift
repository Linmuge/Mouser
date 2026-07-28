import Testing
@testable import MouserNative

@MainActor
private final class FakeAccessibilityAuthorizer: AccessibilityAuthorizing {
    var trusted = false
    private(set) var prompts: [Bool] = []

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return trusted
    }
}

@Suite("Accessibility authorization")
@MainActor
struct AccessibilityAuthorizationTests {
    @Test("workspace refresh uses the native authorization source")
    func refreshesPermissionState() {
        let authorizer = FakeAccessibilityAuthorizer()
        let model = WorkspaceModel.preview

        model.refreshAccessibility(using: authorizer, prompt: false)
        #expect(model.accessibilityGranted == false)

        authorizer.trusted = true
        model.refreshAccessibility(using: authorizer, prompt: true)
        #expect(model.accessibilityGranted)
        #expect(authorizer.prompts == [false, true])
    }
}
