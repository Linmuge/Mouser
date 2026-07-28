import SwiftUI

struct SidebarView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(selection: $model.selectedSection) {
            DeviceSummary(model: model)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
                .listRowBackground(Color.clear)

            Section("设备") {
                ForEach(WorkspaceSection.allCases.prefix(5)) { section in
                    Label(model.localized(section.title), systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Section("Mouser") {
                ForEach(WorkspaceSection.allCases.suffix(2)) { section in
                    Label(model.localized(section.title), systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    StatusDot(active: model.configurationLoaded)
                    Text(model.configurationLoaded ? "原生配置已接通" : "原生迁移中")
                        .font(.caption.weight(.medium))
                }
                Text(model.localizedRuntime(model.configurationStatus))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.ultraThinMaterial)
        }
    }
}

private struct DeviceSummary: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(
                    systemName: model.mouseConnected
                        ? "computermouse.fill"
                        : "computermouse"
                )
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(MouserStyle.accent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, value: model.mouseConnected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.localizedRuntime(model.deviceName))
                        .font(.headline)
                    Text(
                        model.deviceTransport == "—"
                            ? model.localized("等待设备")
                            : model.localizedRuntime(model.deviceTransport)
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                StatusDot(active: model.mouseConnected || model.receiverDetected)
                Text(model.localizedRuntime(model.deviceStatusText))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if model.mouseConnected {
                    Image(systemName: "battery.75percent")
                    Text(model.batteryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .mouserGlass(cornerRadius: 15)
        .animation(MouserMotion.selection, value: model.mouseConnected)
    }
}
