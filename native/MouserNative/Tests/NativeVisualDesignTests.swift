import Foundation
import Testing

@Suite("Native macOS visual design")
struct NativeVisualDesignTests {
    @Test("FundBar dashboard shell replaces the sidebar and floating dock")
    func dashboardShellReplacesSidebarAndDock() throws {
        let content = try source(named: "ContentView.swift")
        let workspace = try source(named: "WorkspaceView.swift")

        #expect(content.contains("MouserWorkspaceView(model: model)"))
        #expect(!content.contains("NavigationSplitView"))
        #expect(!content.contains("DetailedSettingsView"))
        #expect(content.contains("WindowAppearanceBridge(mode: model.appearanceMode)"))

        #expect(workspace.contains("OverviewView(model: model)"))
        #expect(workspace.contains("SectionDetailOverlay"))
        #expect(workspace.contains(".move(edge: .trailing).combined(with: .opacity)"))
        #expect(!workspace.contains("WorkspaceSidebar"))
        #expect(!workspace.contains("PrecisionDock"))
        #expect(!workspace.contains("PrecisionStageRouter"))
        #expect(!workspace.contains("showsDetailedSettings"))
    }

    @Test("window chrome keeps bootstrap-driven visibility and the hidden title bar")
    func windowChromeKeepsBootstrapVisibility() throws {
        let app = try source(named: "MouserNativeApp.swift")

        #expect(app.contains(".windowStyle(.hiddenTitleBar)"))
        #expect(app.contains("model.shouldStartMinimizedAfterBootstrap"))
        #expect(app.contains("model.shouldPresentSettingsAfterBootstrap"))
        #expect(!app.contains("if model.startMinimized"))
    }

    @Test("only the window surface bleeds into the top safe area")
    func onlyWindowSurfaceBleedsIntoSafeArea() throws {
        let workspace = try source(named: "WorkspaceView.swift")

        // Only the window surface may bleed into the top safe area. Extending
        // the whole workspace instead breaks hit-testing in fullscreen windows,
        // which used to leave the button-stage hotspots unclickable.
        #expect(workspace.contains("private struct WorkspaceWindowSurface"))
        #expect(workspace.contains(".ignoresSafeArea()"))
        #expect(!workspace.contains(".ignoresSafeArea(.container, edges: .top)"))
    }

    @Test("dashboard composes hero, function panels, and status rail")
    func dashboardComposesHeroPanelsAndRail() throws {
        let overview = try source(named: "OverviewView.swift")

        for component in [
            "private struct DeviceHeroPanel",
            "struct DPIRangeBar",
            "ButtonMappingPanel(model: model)",
            "struct DashboardPanel",
            "private struct WheelPointerCard",
            "private struct HapticsCard",
            "private struct DeviceStatusPanel",
            "private struct ActionsRingPanel",
            "private struct QuickSettingsPanel",
            "private struct AccessibilityBanner",
        ] {
            #expect(overview.contains(component))
        }

        #expect(overview.contains("model.requestAccessibility()"))
        #expect(overview.contains("model.configurationPersistenceState.message"))
        #expect(overview.contains("case .failed: .red"))
        #expect(overview.contains("model.setStartAtLogin"))
        #expect(overview.contains("GlassEffectContainer"))
        #expect(overview.contains(".onContinuousHover"))
        #expect(overview.contains(".rotation3DEffect"))
        #expect(overview.contains(".contentTransition(.numericText())"))
        #expect(overview.contains("size: 44, weight: .semibold"))
        #expect(
            overview.contains(
                "let resolvedResourceName = resourceName ?? \"mx-master-3s\""
            )
        )
    }

    @Test("toolbar exposes device, profile, permission, appearance, and maintenance")
    func toolbarExposesDeviceAndMaintenanceActions() throws {
        let workspace = try source(named: "WorkspaceView.swift")

        #expect(workspace.contains("当前配置"))
        #expect(workspace.contains("管理配置"))
        #expect(workspace.contains("权限正常"))
        #expect(workspace.contains("需要权限"))
        #expect(workspace.contains("model.requestAccessibility()"))
        #expect(workspace.contains(".buttonStyle(.glass)"))
        #expect(workspace.contains("检查更新"))
        #expect(workspace.contains("model.exportDiagnostics()"))
        #expect(workspace.contains("关于 Mouser"))
        #expect(workspace.contains(".buttonStyle(.glass)"))
        // 顶栏五个控件共用同一枚交互式玻璃胶囊底座。
        #expect(workspace.contains("private struct ToolbarGlassCapsule"))
        #expect(workspace.contains(".glassEffect(.regular.interactive(), in: Capsule())"))

        let toolbarStart = try #require(workspace.range(of: "private struct DeviceMenu"))
        let moreEnd = try #require(workspace.range(of: "更多操作"))
        let toolbarControls = workspace[toolbarStart.lowerBound..<moreEnd.upperBound]
        #expect(!toolbarControls.contains(".buttonStyle(.glass)"))
    }

    @Test("slide-in overlay routes every section destination")
    func overlayRoutesEverySectionDestination() throws {
        let workspace = try source(named: "WorkspaceView.swift")

        for destination in [
            "ButtonsDetailContent(model: model)",
            "PointerScrollView(model: model)",
            "HapticsView(model: model)",
            "ActionsRingSettingsView(model: model)",
            "ProfilesView(model: model)",
            "AdvancedView(model: model)",
        ] {
            #expect(workspace.contains(destination))
        }
        #expect(workspace.contains("model.selectedSection = .overview"))
    }

    @Test("palette pairs Apple-blue chrome with an ambient liquid-glass canvas")
    func paletteUsesQuietNativeTokens() throws {
        let design = try source(named: "DesignSystem.swift")

        for token in [
            "red: 0, green: 113, blue: 227",
            "red: 10, green: 132, blue: 255",
            "red: 10, green: 159, blue: 146",
            "red: 233, green: 234, blue: 238",
        ] {
            #expect(design.contains(token))
        }

        // Liquid Glass is the surface system: ambient orbs refract through
        // real glassEffect cards instead of flat solid panels.
        #expect(design.contains("struct MouserBackground"))
        #expect(design.contains("struct AmbientOrb"))
        #expect(design.contains("RadialGradient"))
        #expect(design.contains(".glassEffect("))
    }

    @Test("cards follow the liquid-glass surface recipe")
    func cardsFollowHairlineSurfaceRecipe() throws {
        let design = try source(named: "DesignSystem.swift")
        let settings = try source(named: "SettingsViews.swift")

        #expect(design.contains("struct MouserGlassCard"))
        #expect(design.contains(".glassEffect("))
        #expect(design.contains("struct MouserHairline"))
        #expect(design.contains("func mouserCard("))
        #expect(design.contains("func mouserHoverLift"))

        #expect(settings.contains("MouserHairline()"))
        #expect(!settings.contains("PrecisionRule"))
        #expect(!settings.contains("showsTopBorder"))
        #expect(!settings.contains("showsFooterRule"))
    }

    @Test("button mapping keeps artwork hotspots on the dashboard")
    func buttonMappingKeepsArtworkHotspots() throws {
        let buttons = try source(named: "ButtonsView.swift")

        for component in [
            "struct ButtonMappingPanel",
            "struct ButtonsDetailContent",
            "MouseButtonStageLayout.layout",
            "MouseImage(resourceName:",
            "ShortcutCaptureSheet",
        ] {
            #expect(buttons.contains(component))
        }

        #expect(buttons.contains("matchedGeometryEffect"))
        #expect(buttons.contains(".onHover"))
        #expect(buttons.contains("glassEffect"))
        #expect(buttons.contains("hscroll_left"))
        #expect(buttons.contains("hscroll_right"))
        #expect(buttons.contains("GestureMappingEditor"))
    }

    @Test("actions ring diagram stays interactive and synced with slot rows")
    func actionsRingDiagramStaysInteractive() throws {
        let settings = try source(named: "SettingsViews.swift")

        #expect(settings.contains("private struct ActionsRingDiagram"))
        #expect(settings.contains("AngularGradient("))
        #expect(settings.contains("model.selectedActionsRingIndex = index"))
        #expect(settings.contains("model.setActionsRingSlot"))
    }

    @Test("settings pages keep every control bound to real model state")
    func settingsPagesKeepRealBindings() throws {
        let settings = try source(named: "SettingsViews.swift")

        for binding in [
            "$model.dpi",
            "$model.invertVerticalScroll",
            "$model.invertHorizontalScroll",
            "$model.hapticsEnabled",
            "model.setStartAtLogin",
            "model.updateStatusText",
            "model.downloadAndInstallLatestUpdate()",
            "model.setActionsRingSlot",
            "model.setDPIPreset",
        ] {
            #expect(settings.contains(binding))
        }

        #expect(!settings.contains("Text(\"已自动保存\")"))
        #expect(!settings.contains("@State private var longPressEnabled"))
        #expect(!settings.contains("@State private var automaticallySwitches"))
        #expect(!settings.contains("@State private var restoresAfterWake"))
    }

    @Test("motion is lively but always gated by Reduce Motion")
    func motionStaysBriefAndAccessible() throws {
        let design = try source(named: "DesignSystem.swift")

        #expect(design.contains("struct MouserRevealModifier"))
        #expect(design.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(design.contains(".opacity("))
        #expect(design.contains(".offset("))
        // The ambient orbs drift forever, so Reduce Motion must pin them still.
        #expect(design.contains("guard !reduceMotion, !drifting else { return }"))
        #expect(design.contains("repeatForever(autoreverses: true)"))
    }

    @Test("window appearance keeps native materials in the selected color scheme")
    func windowAppearanceKeepsNativeMaterials() throws {
        let design = try source(named: "DesignSystem.swift")
        let content = try source(named: "ContentView.swift")

        #expect(design.contains("struct WindowAppearanceBridge"))
        #expect(design.contains("window?.appearance"))
        #expect(design.contains("standardWindowButton(.closeButton)"))
        #expect(design.contains("styleMask.insert(.fullSizeContentView)"))
        #expect(!content.contains(".preferredColorScheme"))
    }

    @Test("isolated visual QA uses the approved full-size viewport")
    func isolatedVisualQAUsesApprovedFullSizeViewport() throws {
        let app = try source(named: "MouserNativeApp.swift")

        #expect(app.contains("previewMode == \"MouserUIPreview\""))
        #expect(app.contains("NSSize(width: 1_320, height: 820)"))
        #expect(app.contains("window.setFrame"))
        #expect(app.contains(".frame(minWidth: 1_052, minHeight: 620)"))
        #expect(app.contains(".defaultSize(width: 1_320, height: 788)"))
    }

    @Test("compact visual QA matches the 1052 by 652 window on the button screen")
    func compactVisualQAMatchesApprovedButtonScreen() throws {
        let app = try source(named: "MouserNativeApp.swift")

        #expect(app.contains("MouserUIPreviewCompact"))
        #expect(app.contains("NSSize(width: 1_052, height: 652)"))
        #expect(app.contains("model.selectedSection = .buttons"))
    }

    private func source(named fileName: String) throws -> String {
        let projectDirectory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectDirectory
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
