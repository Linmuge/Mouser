import Testing
@testable import MouserNative

@Suite("Logitech device catalog")
struct LogitechDeviceCatalogTests {
    @Test("device families select their native DPI range and artwork")
    func profiles() {
        #expect(LogitechDeviceCatalog.profile(named: "MX Master 3S").dpiRange == 200...8_000)
        #expect(LogitechDeviceCatalog.profile(named: "Wireless Mouse MX Master 3").dpiRange == 200...4_000)
        #expect(LogitechDeviceCatalog.profile(named: "MX Vertical").imageResource == "mx_vertical")
        #expect(LogitechDeviceCatalog.profile(named: "MX Anywhere 3S").imageResource == "mouse_mx_anywhere_3s")
        #expect(LogitechDeviceCatalog.profile(named: "G502 X PLUS").dpiRange == 100...25_600)
    }

    @Test("manual layout choices resolve without changing hardware discovery")
    func manualLayouts() {
        #expect(LogitechDeviceCatalog.manualLayoutChoices.first?.key == "")
        #expect(LogitechDeviceCatalog.profile(layoutKey: "mx_vertical")?.imageResource == "mx_vertical")
        #expect(LogitechDeviceCatalog.profile(layoutKey: "unknown") == nil)
    }
}
