import Foundation
import Testing
@testable import MouserNative

@Suite("Application bundle metadata")
struct ApplicationBundleTests {
    @Test("declared application icon exists in the bundle")
    func declaredApplicationIconExists() {
        let bundle = Bundle(for: MouserAppDelegate.self)
        let declaredIcon = bundle.object(
            forInfoDictionaryKey: "CFBundleIconFile"
        ) as? String

        #expect(declaredIcon != nil, "Info.plist 必须声明 CFBundleIconFile")
        guard let declaredIcon else { return }

        let iconURL = URL(fileURLWithPath: declaredIcon)
        let resourceName = iconURL.deletingPathExtension().lastPathComponent
        let resourceExtension = iconURL.pathExtension.isEmpty
            ? "icns"
            : iconURL.pathExtension
        #expect(
            bundle.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ) != nil,
            "CFBundleIconFile 指向的图标必须随 App 一起打包"
        )
    }

    @Test("application version follows build settings")
    func applicationVersionFollowsBuildSettings() {
        let bundle = Bundle(for: MouserAppDelegate.self)

        #expect(
            bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String == "3.8.0"
        )
        #expect(
            bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String == "1"
        )
    }
}
