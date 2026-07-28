import Foundation
import Testing

@Suite("Native macOS visual design")
struct NativeVisualDesignTests {
    @Test("shared design system creates a spatial native scene instead of a flat gray canvas")
    func sharedDesignSystemCreatesSpatialNativeScene() throws {
        let source = try source(named: "DesignSystem.swift")

        #expect(source.contains("struct MouserBackground"))
        #expect(source.contains("struct AmbientOrb"))
        #expect(source.contains("LinearGradient"))
        #expect(source.contains(".blendMode(.plusLighter)"))
        #expect(!source.contains("RadialGradient"))
    }

    @Test("live device values use restrained native motion without toolbar decoration")
    func liveDeviceValuesUseRestrainedNativeMotion() throws {
        let workspace = try source(named: "PrecisionWorkspaceView.swift")
        let overview = try source(named: "OverviewView.swift")
        let sidebar = try source(named: "SidebarView.swift")

        #expect(workspace.contains(".buttonStyle(.glass)"))
        #expect(!workspace.contains(".contentTransition(.symbolEffect(.replace))"))
        #expect(overview.contains(".contentTransition(.numericText())"))
        #expect(sidebar.contains(".symbolEffect(.pulse"))
    }

    @Test("selected precision workspace replaces the split sidebar shell")
    func selectedPrecisionWorkspaceReplacesSplitSidebarShell() throws {
        let content = try source(named: "ContentView.swift")
        let app = try source(named: "MouserNativeApp.swift")

        #expect(content.contains("PrecisionWorkspaceView(model: model)"))
        #expect(!content.contains("NavigationSplitView"))
        #expect(!content.contains("SidebarView"))
        #expect(app.contains(".windowStyle(.hiddenTitleBar)"))
        #expect(workspaceChromeExtendsBehindNativeControls())
    }

    private func workspaceChromeExtendsBehindNativeControls() -> Bool {
        guard let workspace = try? source(named: "PrecisionWorkspaceView.swift") else {
            return false
        }
        return workspace.contains(".ignoresSafeArea(.container, edges: .top)")
    }

    @Test("precision workspace keeps every settings destination in the new stage and inspector")
    func precisionWorkspaceKeepsEverySettingsDestination() throws {
        let workspace = try source(named: "PrecisionWorkspaceView.swift")
        let stages = try source(named: "PrecisionWorkspaceStages.swift")
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")

        for section in [
            "overview", "buttons", "pointerAndScroll", "haptics",
            "actionsRing", "profiles", "advanced",
        ] {
            #expect(workspace.contains("case .\(section):"))
        }

        #expect(stages.contains("MouseButtonStageLayout.layout"))
        #expect(stages.contains("MouseImage(resourceName:"))
        #expect(inspectors.contains("ActionPicker("))
        #expect(inspectors.contains("$model.dpi"))
        #expect(inspectors.contains("$model.invertVerticalScroll"))
        #expect(inspectors.contains("$model.hapticsEnabled"))
        #expect(inspectors.contains("model.setActionsRingSlot"))
        #expect(inspectors.contains("model.setStartAtLogin"))
    }

    @Test("approved B geometry is implemented at full and compact window sizes")
    func approvedBGeometryIsImplementedAtBothWindowSizes() throws {
        let workspace = try source(named: "PrecisionWorkspaceView.swift")

        #expect(workspace.contains("enum PrecisionWorkspaceMetrics"))
        #expect(workspace.contains("width <= 1_120"))
        #expect(workspace.contains("chromeHeight: 58"))
        #expect(workspace.contains("inspectorWidth: compact ? 284 : 314"))
        #expect(workspace.contains("inspectorTrailing: compact ? 18 : 28"))
        #expect(workspace.contains("dockWidth: compact ? 600 : 650"))
        #expect(workspace.contains("showsProfilePill: !compact"))
        #expect(workspace.contains("showsPermissionButton: !compact"))
    }

    @Test("isolated visual QA uses the approved full-size viewport")
    func isolatedVisualQAUsesApprovedFullSizeViewport() throws {
        let app = try source(named: "MouserNativeApp.swift")

        #expect(app.contains("previewMode == \"MouserUIPreview\""))
        #expect(app.contains("NSSize(width: 1_320, height: 820)"))
        #expect(app.contains("window.setFrame"))
    }

    @Test("compact visual QA matches the 1052 by 652 window inside the approved canvas")
    func compactVisualQAMatchesApprovedButtonScreen() throws {
        let app = try source(named: "MouserNativeApp.swift")
        let stages = try source(named: "PrecisionWorkspaceStages.swift")
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")

        #expect(app.contains("MouserUIPreviewCompact"))
        #expect(app.contains("NSSize(width: 1_052, height: 652)"))
        #expect(app.contains(".frame(minWidth: 1_052, minHeight: 620)"))
        #expect(app.contains(".defaultSize(width: 1_320, height: 788)"))
        #expect(app.contains("model.selectedSection = .buttons"))
        #expect(inspectors.contains(".frame(width: 42, height: 24)"))
        #expect(inspectors.contains(".offset(x: isOn ? 9 : -9)"))
        #expect(stages.contains("metrics.mouseImageFrame("))
        #expect(stages.contains("in: imageFrame"))
        #expect(stages.contains("rotationDegrees: 1"))
        #expect(stages.contains(".offset(x: proxy.size.width * 0.50"))
        #expect(inspectors.contains("ScrollView(.vertical, showsIndicators: false)"))
        #expect(inspectors.contains("struct PrecisionActionFieldVisualLabel"))
        #expect(inspectors.contains(".opacity(0.001)"))
        #expect(inspectors.contains("Image(systemName: \"chevron.down\")"))
    }

    @Test("button inspector uses spacing instead of decorative separator rules")
    func buttonInspectorRemovesDecorativeRules() throws {
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")
        let start = try #require(inspectors.range(of: "struct PrecisionButtonsInspector"))
        let end = try #require(inspectors.range(of: "struct PrecisionPointerInspector"))
        let buttonInspector = inspectors[start.lowerBound..<end.lowerBound]

        #expect(!buttonInspector.contains("PrecisionRule()"))
        #expect(!buttonInspector.contains("showsTopBorder"))
        #expect(!buttonInspector.contains("showsFooterRule"))
    }

    @Test("every inspector removes decorative rules and the save footer stays transparent")
    func everyInspectorRemovesDecorativeRules() throws {
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")
        let panelStart = try #require(inspectors.range(of: "private struct PrecisionInspectorPanel"))
        let panelEnd = try #require(inspectors.range(of: "private struct PrecisionSectionGap"))
        let inspectorPanel = inspectors[panelStart.lowerBound..<panelEnd.lowerBound]

        #expect(!inspectors.contains("PrecisionRule"))
        #expect(!inspectors.contains("showsTopBorder"))
        #expect(!inspectors.contains("showsFooterRule"))
        #expect(inspectors.contains("PrecisionSectionGap()"))
        #expect(!inspectorPanel.contains(".background(panelColor)\n"))
        #expect(
            inspectorPanel.contains(
                "VStack(alignment: .leading, spacing: 0) {\n            ScrollView"
            )
        )
    }

    @Test("range sliders keep quantized values without rendering discrete tick marks")
    func rangeSlidersHideStepTickMarks() throws {
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")

        #expect(!inspectors.contains("Slider(value: $value, in: range, step: step)"))
        #expect(inspectors.contains("PrecisionRangeQuantizer.quantize"))
        #expect(inspectors.contains("Slider(value: quantizedValue, in: range)"))
    }

    @Test("every approved B stage is represented instead of a generic mouse scene")
    func everyApprovedBStageIsRepresented() throws {
        let stages = try source(named: "PrecisionWorkspaceStages.swift")

        for component in [
            "PrecisionOverviewQuickLines",
            "PrecisionMetricStrip",
            "PrecisionStageAxis",
            "PrecisionHapticPulseRings",
            "PrecisionEightDirectionRing",
            "PrecisionProfileStageList",
            "PrecisionDiagnosticStagePath",
        ] {
            #expect(stages.contains("struct \(component)"))
        }
        #expect(stages.contains("height: metrics.mouseHeight"))
        #expect(stages.contains("x: size.width * metrics.mouseX"))
        #expect(stages.contains("AngularGradient("))
        #expect(stages.contains("Mission Control"))
        #expect(stages.contains("媒体播放"))
        #expect(stages.contains("截图"))
    }

    @Test("inspectors preserve all controls visible in the approved B screens")
    func inspectorsPreserveApprovedBControls() throws {
        let inspectors = try source(named: "PrecisionWorkspaceInspectors.swift")

        for copy in [
            "恢复状态", "长按动作", "关闭 SmartShift 后", "测试反馈",
            "作用范围", "适用应用", "自动切换", "继承指针设置",
            "唤醒后恢复", "重连后恢复", "诊断日志",
        ] {
            #expect(inspectors.contains("\"\(copy)\""))
        }
    }

    @Test("receiver placeholders retain the default mouse product artwork")
    func receiverPlaceholderRetainsDefaultMouseArtwork() throws {
        let overview = try source(named: "OverviewView.swift")

        #expect(
            overview.contains(
                "let resolvedResourceName = resourceName ?? \"mx-master-3s\""
            )
        )
    }

    @Test("overview centers the product in an asymmetric device stage")
    func overviewUsesAsymmetricDeviceStage() throws {
        let overview = try source(named: "OverviewView.swift")

        #expect(overview.contains("private struct DeviceHeroStage"))
        #expect(overview.contains("private struct DeviceTelemetryRail"))
        #expect(overview.contains("private struct QuickControlDock"))
        #expect(overview.contains(".frame(maxWidth: 520, maxHeight: 360)"))
        #expect(!overview.contains("DeviceSummaryCard"))
        #expect(!overview.contains("MetricTile"))
        #expect(!overview.contains("RadialGradient"))
    }

    @Test("button mapping uses a focused studio instead of two unrelated gray cards")
    func buttonMappingUsesFocusedStudio() throws {
        let buttons = try source(named: "ButtonsView.swift")

        #expect(buttons.contains("private struct ButtonMappingStudio"))
        #expect(buttons.contains("private struct MouseButtonStageBackdrop"))
        #expect(buttons.contains("private struct MappingInspector"))
        #expect(buttons.contains(".offset(x: -18)"))
    }

    @Test("motion is brief, transform based, and respects Reduce Motion")
    func motionIsBriefTransformBasedAndAccessible() throws {
        let design = try source(named: "DesignSystem.swift")

        #expect(design.contains("struct MouserRevealModifier"))
        #expect(design.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(design.contains(".opacity("))
        #expect(design.contains(".offset("))
        #expect(design.contains(".scaleEffect("))
        #expect(!design.contains("repeatForever"))
    }

    @Test("device artwork and button selection respond directly to pointer actions")
    func deviceArtworkAndButtonSelectionRespondToPointer() throws {
        let overview = try source(named: "OverviewView.swift")
        let buttons = try source(named: "ButtonsView.swift")

        #expect(overview.contains(".onContinuousHover"))
        #expect(overview.contains(".rotation3DEffect"))
        #expect(buttons.contains("matchedGeometryEffect"))
        #expect(buttons.contains(".onHover"))
    }

    @Test("window appearance keeps native materials in the selected color scheme")
    func windowAppearanceKeepsNativeMaterialsInSync() throws {
        let design = try source(named: "DesignSystem.swift")
        let content = try source(named: "ContentView.swift")

        #expect(design.contains("struct WindowAppearanceBridge"))
        #expect(design.contains("window?.appearance"))
        #expect(
            content.contains(
                "WindowAppearanceBridge(mode: model.appearanceMode)"
            )
        )
        #expect(design.contains("standardWindowButton(.closeButton)"))
        #expect(design.contains("styleMask.insert(.fullSizeContentView)"))
        #expect(!content.contains(".preferredColorScheme"))
    }

    @Test("title bar and workspace share one continuous window surface")
    func titleBarAndWorkspaceShareOneContinuousSurface() throws {
        let workspace = try source(named: "PrecisionWorkspaceView.swift")
        let titleBarStart = try #require(
            workspace.range(of: "private struct PrecisionTitleBar")
        )
        let titleBarEnd = try #require(
            workspace.range(of: "private struct PrecisionDeviceMenu")
        )
        let titleBar = String(workspace[titleBarStart.lowerBound..<titleBarEnd.lowerBound])

        #expect(workspace.contains("PrecisionWindowSurface()"))
        #expect(!titleBar.contains("LinearGradient("))
        #expect(!titleBar.contains(".background(.ultraThinMaterial)"))
        #expect(!titleBar.contains("@Environment(\\.colorScheme)"))
        #expect(!titleBar.contains("private var surface"))
    }

    @Test("precision palette uses the approved B light and dark tokens")
    func precisionPaletteUsesApprovedBTokens() throws {
        let design = try source(named: "DesignSystem.swift")

        for token in [
            "10, green: 159, blue: 146",
            "50, green: 214, blue: 194",
            "49, green: 184, blue: 117",
            "72, green: 217, blue: 144",
            "112, green: 121, blue: 124",
            "155, green: 166, blue: 164",
        ] {
            #expect(design.contains(token))
        }
        #expect(design.contains("static let muted"))
        #expect(design.contains("static let ink"))
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
