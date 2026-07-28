import ApplicationServices
import Foundation

@MainActor
protocol AccessibilityAuthorizing: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
}

@MainActor
final class SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    func isTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
