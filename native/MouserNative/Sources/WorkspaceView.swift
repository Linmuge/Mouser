import AppKit
import SwiftUI

/// 主窗口骨架，FundBar 式单页仪表盘：
/// 顶部工具条 + 滚动仪表盘；深入编辑用右侧滑入面板 + 背景压暗，没有常驻侧边栏。
struct MouserWorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var showsAbout = false

    var body: some View {
        ZStack(alignment: .top) {
            WorkspaceWindowSurface(model: model)

            VStack(spacing: 0) {
                WorkspaceToolbar(model: model, showsAbout: $showsAbout)
                    .frame(height: 52)

                OverviewView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.selectedSection != .overview {
                SectionDetailOverlay(model: model)
            }
        }
        .background {
            WindowAppearanceBridge(mode: model.appearanceMode)
        }
        .sheet(isPresented: $showsAbout) {
            MouserAboutView(version: model.currentVersion)
        }
        .tint(MouserStyle.accent)
    }
}

// MARK: - 窗口表面

private struct WorkspaceWindowSurface: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        // 液态玻璃需要背后的色彩才会折射：动态环境光画布。
        // The surface is the only layer that bleeds into the top safe area;
        // extending the whole workspace instead breaks hit-testing in fullscreen.
        MouserBackground(
            glow: model.mouseConnected || model.receiverDetected
                ? MouserStyle.ambientTeal
                : MouserStyle.warning
        )
    }
}

// MARK: - 工具条

private struct WorkspaceToolbar: View {
    @Bindable var model: WorkspaceModel
    @Binding var showsAbout: Bool

    var body: some View {
        HStack(spacing: 10) {
            DeviceMenu(model: model)
                .padding(.leading, 8)

            Spacer(minLength: 12)

            ProfileMenu(model: model)
            PermissionButton(model: model)
            AppearanceMenu(model: model)
            MoreMenu(model: model, showsAbout: $showsAbout)
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            MouserHairline(leadingInset: 0)
                .padding(.horizontal, -20)
        }
    }
}

/// 顶栏五个控件共用的底座：同高度、同内距、同一枚交互式玻璃胶囊。
private struct ToolbarGlassCapsule: ViewModifier {
    var iconOnly = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(width: iconOnly ? 32 : nil, height: 32)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
    }
}

extension View {
    fileprivate func toolbarGlassCapsule(iconOnly: Bool = false) -> some View {
        modifier(ToolbarGlassCapsule(iconOnly: iconOnly))
    }
}

private struct DeviceMenu: View {
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
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .toolbarGlassCapsule()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("概览")
    }
}

private struct ProfileMenu: View {
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
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 7)
                Text(model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 7)
            }
            .font(.system(size: 12.5))
            .toolbarGlassCapsule()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("切换应用配置")
    }
}

private struct PermissionButton: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Button {
            if model.accessibilityGranted {
                model.refreshAccessibility(prompt: false)
            } else {
                model.requestAccessibility()
            }
        } label: {
            HStack(spacing: 7) {
                StatusDot(active: model.accessibilityGranted)
                Text(model.accessibilityGranted ? "权限正常" : "需要权限")
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(model.accessibilityGranted ? .secondary : MouserStyle.warning)
            .toolbarGlassCapsule()
        }
        .buttonStyle(.plain)
        .help(model.accessibilityGranted ? "重新检查辅助功能权限" : "授予辅助功能权限")
    }
}

private struct AppearanceMenu: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        Menu {
            Picker("界面外观", selection: $model.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.title)).tag(mode)
                }
            }
        } label: {
            Image(systemName: model.appearanceMode == .dark ? "moon.fill" : "circle.lefthalf.filled")
                .font(.system(size: 13, weight: .medium))
                .toolbarGlassCapsule(iconOnly: true)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("切换深浅色")
    }
}

private struct MoreMenu: View {
    @Bindable var model: WorkspaceModel
    @Binding var showsAbout: Bool

    var body: some View {
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
                .font(.system(size: 13, weight: .semibold))
                .toolbarGlassCapsule(iconOnly: true)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("更多操作")
    }
}

// MARK: - 滑入式编辑面板（FundBar EditHoldingView 同款交互）

private struct SectionDetailOverlay: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(reduceMotion ? 0.12 : 0.08)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }
                .transition(.opacity)

            VStack(spacing: 0) {
                overlayHeader

                ScrollView {
                    sectionContent
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 468)
            .frame(maxHeight: .infinity)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: MouserStyle.radiusPanel + 2, style: .continuous)
            )
            .shadow(color: .black.opacity(0.20), radius: 30, x: -8)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.12),
            value: model.selectedSection
        )
    }

    private var overlayHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(sectionTitle))
                    .font(.system(size: 17, weight: .semibold))
                Text(LocalizedStringKey(sectionSubtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.glass)
            .help("关闭")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            MouserHairline(leadingInset: 0)
                .padding(.horizontal, -20)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.selectedSection {
        case .overview:
            EmptyView()
        case .buttons:
            ButtonsDetailContent(model: model)
        case .pointerAndScroll:
            PointerScrollView(model: model)
        case .haptics:
            HapticsView(model: model)
        case .actionsRing:
            ActionsRingSettingsView(model: model)
        case .profiles:
            ProfilesView(model: model)
        case .advanced:
            AdvancedView(model: model)
        }
    }

    private func close() {
        model.selectedSection = .overview
    }

    private var sectionTitle: String {
        switch model.selectedSection {
        case .overview: model.localized("概览")
        case .buttons: model.localized("按键")
        case .pointerAndScroll: model.localized("指针与滚动")
        case .haptics: model.localized("触觉反馈")
        case .actionsRing: model.localized("操作环")
        case .profiles: model.localized("应用配置")
        case .advanced: model.localized("高级")
        }
    }

    private var sectionSubtitle: String {
        switch model.selectedSection {
        case .overview: ""
        case .buttons: model.localized("选择按键，再设置动作。")
        case .pointerAndScroll: model.localized("调整 DPI、滚轮模式和方向。")
        case .haptics: model.localized("调整强度和触发方式。")
        case .actionsRing: model.localized("为八个方向设置动作。")
        case .profiles: model.localized("为不同应用保存独立设置。")
        case .advanced: model.localized("管理启动、恢复和更新。")
        }
    }
}

// MARK: - 关于

struct MouserAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let version: String

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
            Text("Mouser")
                .font(.system(size: 22, weight: .semibold))
            Text("v\(version) Swift 原生版")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Forked from TomBadash/Mouser · 感谢原作者 Tom Badash")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 4)
        }
        .padding(30)
        .frame(width: 380)
    }
}
