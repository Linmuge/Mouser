import AppKit
import SwiftUI

struct PrecisionWorkspaceLayout: Equatable {
    let compact: Bool
    let chromeHeight: CGFloat
    let workspaceTop: CGFloat
    let contextLeading: CGFloat
    let contextTop: CGFloat
    let contextWidth: CGFloat
    let contextTitleSize: CGFloat
    let objectStageTrailing: CGFloat
    let objectStageBottom: CGFloat
    let inspectorWidth: CGFloat
    let inspectorTrailing: CGFloat
    let inspectorTop: CGFloat
    let inspectorBottom: CGFloat
    let dockWidth: CGFloat
    let dockBottom: CGFloat
    let profileLeading: CGFloat
    let profileBottom: CGFloat
    let showsProfilePill: Bool
    let showsPermissionButton: Bool
}

enum PrecisionWorkspaceMetrics {
    static func layout(width: CGFloat) -> PrecisionWorkspaceLayout {
        let compact = width <= 1_120
        return PrecisionWorkspaceLayout(
            compact: compact,
            chromeHeight: 58,
            workspaceTop: 52,
            contextLeading: compact ? 28 : 38,
            contextTop: 36,
            contextWidth: compact ? 315 : 390,
            contextTitleSize: compact ? 32 : 39,
            objectStageTrailing: compact ? 302 : 342,
            objectStageBottom: 78,
            inspectorWidth: compact ? 284 : 314,
            inspectorTrailing: compact ? 18 : 28,
            inspectorTop: 104,
            inspectorBottom: 98,
            dockWidth: compact ? 600 : 650,
            dockBottom: 18,
            profileLeading: 38,
            profileBottom: 27,
            showsProfilePill: !compact,
            showsPermissionButton: !compact
        )
    }
}

struct PrecisionWorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @Namespace private var navigationNamespace
    @State private var showsAbout = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionWorkspaceMetrics.layout(width: proxy.size.width)
            let stageSize = CGSize(
                width: proxy.size.width - metrics.objectStageTrailing,
                height: proxy.size.height - metrics.workspaceTop - metrics.objectStageBottom
            )
            let inspectorHeight = proxy.size.height
                - metrics.workspaceTop
                - metrics.inspectorTop
                - metrics.inspectorBottom

            ZStack(alignment: .topLeading) {
                PrecisionWindowSurface()

                PrecisionTitleBar(
                    model: model,
                    metrics: metrics,
                    showsAbout: $showsAbout
                )
                .frame(width: proxy.size.width, height: metrics.chromeHeight)

                PrecisionStageRouter(model: model, metrics: metrics)
                    .frame(width: stageSize.width, height: stageSize.height)
                    .offset(y: metrics.workspaceTop)

                PrecisionContextHeader(model: model, metrics: metrics)
                    .frame(width: metrics.contextWidth, alignment: .leading)
                    .offset(
                        x: metrics.contextLeading,
                        y: metrics.workspaceTop + metrics.contextTop
                    )

                PrecisionInspectorRouter(model: model)
                    .frame(width: metrics.inspectorWidth, height: inspectorHeight)
                    .offset(
                        x: proxy.size.width
                            - metrics.inspectorTrailing
                            - metrics.inspectorWidth,
                        y: metrics.workspaceTop + metrics.inspectorTop
                    )

                if metrics.showsProfilePill {
                    PrecisionProfileMenu(model: model)
                        .offset(
                            x: metrics.profileLeading,
                            y: proxy.size.height - metrics.profileBottom - 36
                        )
                }

                PrecisionDock(
                    model: model,
                    namespace: navigationNamespace,
                    compact: metrics.compact
                )
                .frame(width: metrics.dockWidth, height: 58)
                .offset(
                    x: (proxy.size.width - metrics.dockWidth) / 2,
                    y: proxy.size.height - metrics.dockBottom - 58
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background {
            WindowAppearanceBridge(mode: model.appearanceMode)
        }
        .sheet(isPresented: $showsAbout) {
            PrecisionAboutView(version: model.currentVersion)
        }
        .tint(MouserStyle.accent)
    }
}

private struct PrecisionWindowSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? Color(red: 17 / 255, green: 25 / 255, blue: 26 / 255)
            : Color(red: 249 / 255, green: 250 / 255, blue: 250 / 255))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.30))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }
}

private struct PrecisionTitleBar: View {
    @Bindable var model: WorkspaceModel
    let metrics: PrecisionWorkspaceLayout
    @Binding var showsAbout: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                PrecisionDeviceMenu(model: model)
                    .padding(.leading, metrics.compact ? 90 : 104)

                Spacer()

                PrecisionChromeActions(
                    model: model,
                    showsPermissionButton: metrics.showsPermissionButton,
                    showsAbout: $showsAbout
                )
                .padding(.trailing, 15)
            }

            HStack(spacing: 7) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                Text("Mouser")
                    .font(.system(size: 13, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct PrecisionDeviceMenu: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Menu {
            Label(
                model.localizedRuntime(model.deviceStatusText),
                systemImage: model.mouseConnected || model.receiverDetected
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle"
            )
            Divider()
            Button("概览", systemImage: "macwindow") {
                model.selectedSection = .overview
            }
            Button("设备识别", systemImage: "computermouse") {
                model.selectedSection = .advanced
            }
        } label: {
            HStack(spacing: 8) {
                StatusDot(active: model.mouseConnected || model.receiverDetected)
                Text(model.localizedRuntime(model.deviceName))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MouserStyle.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("选择设备")
    }
}

private struct PrecisionChromeActions: View {
    @Bindable var model: WorkspaceModel
    let showsPermissionButton: Bool
    @Binding var showsAbout: Bool

    var body: some View {
        HStack(spacing: 1) {
            if showsPermissionButton {
                Button {
                    if model.accessibilityGranted {
                        model.refreshAccessibility(prompt: false)
                    } else {
                        model.requestAccessibility()
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(active: model.accessibilityGranted)
                        Text(model.accessibilityGranted ? "权限正常" : "需要权限")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .contentShape(Capsule())
                }
                .buttonStyle(.glass)
            }

            Menu {
                Picker("界面外观", selection: $model.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
            } label: {
                Image(systemName: model.appearanceMode == .dark ? "moon.fill" : "circle.lefthalf.filled")
                    .frame(width: 31, height: 30)
                    .contentShape(Circle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("切换深浅色")

            Menu {
                Button("检查更新", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.checkForUpdates() }
                }
                Button("导出诊断信息", systemImage: "doc.text") {
                    model.exportDiagnostics()
                }
                Divider()
                Button("关于 Mouser", systemImage: "info.circle") {
                    showsAbout = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 31, height: 30)
                    .contentShape(Circle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
        .padding(2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}

private struct PrecisionContextHeader: View {
    @Bindable var model: WorkspaceModel
    let metrics: PrecisionWorkspaceLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(title))
                .font(.system(size: metrics.contextTitleSize, weight: .bold))
                .tracking(-metrics.contextTitleSize * 0.045)
                .lineSpacing(0)
                .contentTransition(.numericText())

            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 15))
                .foregroundStyle(MouserStyle.muted)
                .padding(.top, 9)

            HStack(spacing: 11) {
                StatusDot(active: model.mouseConnected || model.receiverDetected)
                Text(model.localizedRuntime(model.deviceName))
                    .fontWeight(.bold)
                Text(statusText)
                    .foregroundStyle(MouserStyle.muted)
            }
            .font(.system(size: 13))
            .padding(.top, 20)
        }
        .animation(MouserMotion.selection, value: model.selectedSection)
    }

    private var statusText: String {
        let profile = model.localizedRuntime(model.selectedProfile?.name ?? "默认配置")
        if model.mouseConnected {
            return model.formatted("已连接 · %@ · %@", model.batteryStatusText, profile)
        }
        return model.formatted("未连接 · %@", profile)
    }

    private var title: String {
        switch model.selectedSection {
        case .overview: "设备已就绪"
        case .buttons: "按键映射"
        case .pointerAndScroll: "指针与滚动"
        case .haptics: "触觉反馈"
        case .actionsRing: "Actions Ring"
        case .profiles: "应用配置"
        case .advanced: "高级"
        }
    }

    private var subtitle: String {
        switch model.selectedSection {
        case .overview: "查看连接、权限和当前设置。"
        case .buttons: "选择按键，再设置动作。"
        case .pointerAndScroll: "调整 DPI、滚轮模式和方向。"
        case .haptics: "调整强度和触发方式。"
        case .actionsRing: "为八个方向设置动作。"
        case .profiles: "为不同应用保存独立设置。"
        case .advanced: "管理启动、恢复和更新。"
        }
    }
}

private struct PrecisionStageRouter: View {
    @Bindable var model: WorkspaceModel
    let metrics: PrecisionWorkspaceLayout

    var body: some View {
        Group {
            switch model.selectedSection {
            case .overview:
                PrecisionOverviewStage(model: model, compact: metrics.compact)
            case .buttons:
                PrecisionButtonsStage(model: model, compact: metrics.compact)
            case .pointerAndScroll:
                PrecisionPointerStage(model: model, compact: metrics.compact)
            case .haptics:
                PrecisionHapticsStage(model: model, compact: metrics.compact)
            case .actionsRing:
                PrecisionActionsRingStage(model: model, compact: metrics.compact)
            case .profiles:
                PrecisionProfilesStage(model: model, compact: metrics.compact)
            case .advanced:
                PrecisionAdvancedStage(model: model, compact: metrics.compact)
            }
        }
        .clipped()
        .id(model.selectedSection)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .animation(MouserMotion.selection, value: model.selectedSection)
    }
}

private struct PrecisionInspectorRouter: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Group {
            switch model.selectedSection {
            case .overview:
                PrecisionOverviewInspector(model: model)
            case .buttons:
                PrecisionButtonsInspector(model: model)
            case .pointerAndScroll:
                PrecisionPointerInspector(model: model)
            case .haptics:
                PrecisionHapticsInspector(model: model)
            case .actionsRing:
                PrecisionActionsRingInspector(model: model)
            case .profiles:
                PrecisionProfilesInspector(model: model)
            case .advanced:
                PrecisionAdvancedInspector(model: model)
            }
        }
        .id(model.selectedSection)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(MouserMotion.selection, value: model.selectedSection)
    }
}

private struct PrecisionDock: View {
    @Bindable var model: WorkspaceModel
    let namespace: Namespace.ID
    let compact: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceSection.allCases) { section in
                Button {
                    withAnimation(MouserMotion.selection) {
                        model.selectedSection = section
                    }
                } label: {
                    Text(LocalizedStringKey(shortTitle(for: section)))
                        .font(.system(size: 12, weight: model.selectedSection == section ? .bold : .regular))
                        .foregroundStyle(model.selectedSection == section ? MouserStyle.accent : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if model.selectedSection == section {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(MouserStyle.accent.opacity(0.13))
                                    .matchedGeometryEffect(id: "precision-dock-selection", in: namespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(minWidth: compact ? 72 : 82, maxWidth: .infinity)
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.11), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }

    private func shortTitle(for section: WorkspaceSection) -> String {
        switch section {
        case .overview: "概览"
        case .buttons: "按键"
        case .pointerAndScroll: "指针与滚动"
        case .haptics: "触觉"
        case .actionsRing: "Ring"
        case .profiles: "配置"
        case .advanced: "高级"
        }
    }
}

private struct PrecisionProfileMenu: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Menu {
            ForEach(model.profiles) { profile in
                Button {
                    model.selectProfile(id: profile.id)
                } label: {
                    Label(
                        model.localizedRuntime(profile.name),
                        systemImage: profile.id == model.selectedProfileID ? "checkmark" : profile.systemImage
                    )
                }
            }
            Divider()
            Button("管理配置", systemImage: "slider.horizontal.3") {
                model.selectedSection = .profiles
            }
        } label: {
            HStack(spacing: 0) {
                Text("当前配置")
                    .foregroundStyle(MouserStyle.muted)
                    .padding(.trailing, 8)
                Text(model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MouserStyle.muted)
                    .padding(.leading, 8)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.8) }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 7)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

private struct PrecisionAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let version: String

    var body: some View {
        VStack(spacing: 15) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
            Text("Mouser")
                .font(.system(size: 26, weight: .bold))
            Text("v\(version) Swift 原生版")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MouserStyle.muted)
            Text("Forked from TomBadash/Mouser · 感谢原作者 Tom Badash")
                .font(.caption)
                .foregroundStyle(MouserStyle.muted)
                .multilineTextAlignment(.center)
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(34)
        .frame(width: 400)
    }
}
