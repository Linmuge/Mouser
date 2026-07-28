import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 205, ideal: 226, max: 260)
        } detail: {
            DetailView(model: model)
                .navigationTitle(model.localized(model.selectedSection.title))
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ProfilePicker(model: model)
                    }
                    ToolbarItemGroup {
                        Button("添加配置", systemImage: "plus") {
                            model.selectedSection = .profiles
                        }
                        .help("为一个应用添加独立配置")

                        Menu {
                            Button("检查更新", systemImage: "arrow.triangle.2.circlepath") {
                                Task { await model.checkForUpdates() }
                            }
                            Button("导出诊断信息", systemImage: "doc.text") {
                                model.exportDiagnostics()
                            }
                            Divider()
                            Button("关于 Mouser", systemImage: "info.circle") {}
                        } label: {
                            Label("更多", systemImage: "ellipsis")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(MouserStyle.accent)
        .preferredColorScheme(model.appearanceMode.colorScheme)
    }
}

private struct ProfilePicker: View {
    @Bindable var model: WorkspaceModel

    private var selection: Binding<String> {
        Binding(
            get: { model.selectedProfileID },
            set: { model.selectProfile(id: $0) }
        )
    }

    var body: some View {
        Picker("当前配置", selection: selection) {
            ForEach(model.profiles) { profile in
                Label(model.localized(profile.name), systemImage: profile.systemImage)
                    .tag(profile.id)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 170)
        .accessibilityHint("选择正在编辑的应用配置")
    }
}

private struct DetailView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            if model.showsPermissionCallout {
                PermissionCallout(model: model)
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
            }

            Group {
                switch model.selectedSection {
                case .overview:
                    OverviewView(model: model)
                case .buttons:
                    ButtonsView(model: model)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.035), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

private struct PermissionCallout: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(MouserStyle.warning)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("需要辅助功能权限")
                    .font(.headline)
                Text("允许后 Mouser 才能监听鼠标按键和调整滚轮方向。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("请求权限") {
                model.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            Button("重新检查") {
                model.refreshAccessibility(prompt: false)
            }
        }
        .padding(14)
        .mouserGlass(cornerRadius: 16)
    }
}
