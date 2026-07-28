import AppKit
import Darwin
import SwiftUI

@main
struct MouserNativeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: MouserAppDelegate

    var body: some Scene {
        Window("Mouser", id: "settings") {
            ContentView(model: appDelegate.model)
                .frame(minWidth: 1_052, minHeight: 620)
                .environment(\.locale, appDelegate.model.language.locale)
        }
        .defaultSize(width: 1_320, height: 788)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MouserMenuBarContent(model: appDelegate.model)
                .environment(\.locale, appDelegate.model.language.locale)
        } label: {
            Label("Mouser", systemImage: appDelegate.model.mouseConnected ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class MouserAppDelegate: NSObject, NSApplicationDelegate {
    let model: WorkspaceModel
    private var runtimeTask: Task<Void, Never>?

    override init() {
        let previewMode = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
        if previewMode == "MouserUIPreview" || previewMode == "MouserUIPreviewCompact" {
            model = .preview
        } else {
            model = .live()
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard MacUpdateInstallHelper.runIfRequested() else { return }
        NSApp.setActivationPolicy(.prohibited)
        Darwin.exit(EXIT_SUCCESS)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let previewMode = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
        if previewMode == "MouserUIPreview" || previewMode == "MouserUIPreviewCompact" {
            configureVisualPreviewWindow()
            return
        }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        MacUpdateInstallHelper.cleanupCompletedInstall()
        runtimeTask = Task { [weak self] in
            guard let self else { return }
            await model.bootstrap()
            if model.startMinimized {
                await Task.yield()
                for window in NSApp.windows where window.canBecomeMain {
                    window.orderOut(nil)
                }
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.model.monitorAccessibility() }
                group.addTask { await self.model.monitorLogitechDevices() }
                group.addTask { await self.model.monitorConsoleLock() }
                await group.waitForAll()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeTask?.cancel()
    }

    private func configureVisualPreviewWindow() {
        Task { @MainActor in
            for _ in 0..<20 {
                if let window = NSApp.windows.first(where: \.canBecomeMain) {
                    let compact = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == "MouserUIPreviewCompact"
                    let approvedSize = compact
                        ? NSSize(width: 1_052, height: 652)
                        : NSSize(width: 1_320, height: 820)
                    if compact {
                        model.selectedSection = .buttons
                    }
                    var frame = window.frame
                    frame.origin.y += frame.height - approvedSize.height
                    frame.size = approvedSize
                    window.setFrame(frame, display: true)
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = sender.windows.first(where: \.canBecomeMain) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

private struct MouserMenuBarContent: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 Mouser 设置", systemImage: "gearshape") {
            openSettings()
        }

        Button(
            model.localized(model.remappingEnabled ? "暂停按键映射" : "启用按键映射"),
            systemImage: model.remappingEnabled ? "pause.circle" : "play.circle"
        ) {
            model.setRemappingEnabled(!model.remappingEnabled)
        }

        Divider()

        Label(model.localized(model.deviceStatusText), systemImage: model.mouseConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
        Label(
            model.formatted(
                "电量 %@",
                model.localizedRuntime(model.batteryStatusText)
            ),
            systemImage: model.batteryCharging ? "battery.100percent.bolt" : "battery.75percent"
        )

        Divider()

        if !model.accessibilityGranted {
            Button("授予辅助功能权限", systemImage: "hand.raised") {
                model.requestAccessibility()
                openSettings()
            }
        }
        Button("检查更新…", systemImage: "arrow.triangle.2.circlepath") {
            openSettings(section: .advanced)
            Task { await model.checkForUpdates() }
        }

        Divider()

        Button("退出 Mouser", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openSettings(section: WorkspaceSection? = nil) {
        if let section { model.selectedSection = section }
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
