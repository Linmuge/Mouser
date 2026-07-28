import SwiftUI

struct OverviewView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: model.localizedRuntime(model.deviceName),
                    subtitle: model.deviceTransport == "—"
                        ? "设备状态和常用设置集中在这里。"
                        : model.nativeHIDControlConnected
                            ? model.formatted(
                                "通过 %@ 连接 · 原生设备控制已接管",
                                model.localizedRuntime(model.deviceTransport)
                            )
                            : model.formatted(
                                "通过 %@ 检测 · 原生控制尚未接管",
                                model.localizedRuntime(model.deviceTransport)
                            )
                )

                HStack(alignment: .top, spacing: 20) {
                    MouseHero(model: model)
                        .frame(height: 310)
                    VStack(spacing: 14) {
                        MetricTile(icon: "cursorarrow.motionlines", value: "\(Int(model.dpi))", label: "DPI")
                        MetricTile(
                            icon: model.batteryCharging ? "battery.100percent.bolt" : "battery.75percent",
                            value: model.localizedRuntime(model.batteryStatusText),
                            label: "电量"
                        )
                        MetricTile(icon: "arrow.up.and.down", value: model.scrollModeText, label: "滚轮模式")
                    }
                    .frame(width: 190)
                    .frame(height: 310)
                }

                SettingsGroup("快速设置", caption: "修改会自动保存到当前应用配置。") {
                    SettingRow(title: "SmartShift", detail: "根据滚动速度自动切换棘轮与飞轮") {
                        Toggle("SmartShift", isOn: $model.smartShiftEnabled)
                    }
                    Divider().padding(.leading, 16)
                    SettingRow(title: "反转垂直滚动", detail: "只影响外接鼠标，不改变触控板") {
                        Toggle("反转垂直滚动", isOn: $model.invertVerticalScroll)
                    }
                    Divider().padding(.leading, 16)
                    SettingRow(title: "当前应用配置") {
                        Text(model.selectedProfile?.name ?? "默认")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MouseHero: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MouserStyle.accent.opacity(0.14), Color.accentColor.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                MouseImage(resourceName: model.deviceProfile.imageResource)
                .padding(26)
                .shadow(color: .black.opacity(0.16), radius: 24, y: 15)

            VStack {
                HStack {
                    Label(model.localized(model.deviceStatusText), systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            (model.mouseConnected || model.receiverDetected)
                                ? MouserStyle.connected
                                : .secondary
                        )
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
    }
}

struct MouseImage: View {
    var resourceName: String? = "mx-master-3s"

    var body: some View {
        if let resourceName,
           let imageURL = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "computermouse.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tertiary)
                .padding(70)
        }
    }
}

private struct MetricTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(MouserStyle.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(value))
                    .font(.headline)
                    .lineLimit(1)
                Text(LocalizedStringKey(label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .mouserGlass(cornerRadius: 16)
    }
}
