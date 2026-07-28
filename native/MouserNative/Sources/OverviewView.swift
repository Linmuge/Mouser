import SwiftUI

struct OverviewView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(
                    title: model.localizedRuntime(model.deviceName),
                    subtitle: model.deviceTransport == "—"
                        ? "让鼠标成为工作流的一部分。"
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

                DeviceHeroStage(model: model)
                    .mouserReveal(delay: 0.04)

                QuickControlDock(model: model)
                    .mouserReveal(delay: 0.09)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DeviceHeroStage: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            DeviceArtwork(resourceName: model.deviceProfile.imageResource)
                .frame(maxWidth: .infinity)

            DeviceTelemetryRail(model: model)
                .frame(width: 292)
                .padding(.trailing, 18)
        }
        .frame(minHeight: 420)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            MouserStyle.accent.opacity(0.13),
                            Color.clear,
                            MouserStyle.accentBlue.opacity(0.07),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.50), Color.primary.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 34, y: 18)
    }
}

private struct DeviceArtwork: View {
    let resourceName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var hoverOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AmbientOrb(
                    color: MouserStyle.accent,
                    size: min(proxy.size.width * 0.76, 360)
                )
                .opacity(isHovered ? 0.92 : 0.66)
                .offset(
                    x: -hoverOffset.width * 1.1,
                    y: -hoverOffset.height * 1.1
                )

                Circle()
                    .stroke(MouserStyle.accent.opacity(0.12), lineWidth: 1)
                    .frame(width: 286, height: 286)
                    .scaleEffect(isHovered ? 1.05 : 1)

                Circle()
                    .stroke(MouserStyle.accentBlue.opacity(0.10), lineWidth: 1)
                    .frame(width: 222, height: 222)
                    .scaleEffect(isHovered ? 0.96 : 1)

                MouseImage(resourceName: resourceName)
                    .frame(maxWidth: 520, maxHeight: 360)
                    .scaleEffect(isHovered && !reduceMotion ? 1.035 : 1)
                    .rotation3DEffect(
                        .degrees(Double(-hoverOffset.height) * 0.26),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.58
                    )
                    .rotation3DEffect(
                        .degrees(Double(hoverOffset.width) * 0.26),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.58
                    )
                    .offset(hoverOffset)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.24 : 0.18),
                        radius: isHovered ? 34 : 28,
                        y: isHovered ? 22 : 17
                    )
                    .padding(22)

                VStack {
                    HStack {
                        Label("DEVICE 01", systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(MouserStyle.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                updateHover(phase, in: proxy.size)
            }
            .animation(
                reduceMotion ? nil : MouserMotion.hover,
                value: isHovered
            )
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func updateHover(_ phase: HoverPhase, in size: CGSize) {
        guard !reduceMotion else {
            isHovered = false
            hoverOffset = .zero
            return
        }

        switch phase {
        case .active(let location):
            let width = max(size.width, 1)
            let height = max(size.height, 1)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isHovered = true
                hoverOffset = CGSize(
                    width: (location.x / width - 0.5) * 18,
                    height: (location.y / height - 0.5) * 13
                )
            }
        case .ended:
            withAnimation(MouserMotion.selection) {
                isHovered = false
                hoverOffset = .zero
            }
        }
    }
}

private struct DeviceTelemetryRail: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DeviceStatusPill(
                active: model.mouseConnected || model.receiverDetected,
                title: model.localizedRuntime(model.deviceStatusText)
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("DPI")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text("\(Int(model.dpi))")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .tracking(-1.8)
                    .contentTransition(.numericText())
                Text("指针精度")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .animation(MouserMotion.selection, value: model.dpi)

            Divider()

            TelemetryItem(
                icon: model.batteryCharging
                    ? "battery.100percent.bolt"
                    : "battery.75percent",
                label: "电量",
                value: model.localizedRuntime(model.batteryStatusText),
                tint: MouserStyle.connected
            )

            TelemetryItem(
                icon: "circle.grid.cross",
                label: "滚轮",
                value: model.scrollModeText,
                tint: MouserStyle.accentBlue
            )

            Spacer(minLength: 0)

            Label(
                model.nativeHIDControlConnected ? "原生控制在线" : "等待原生控制",
                systemImage: model.nativeHIDControlConnected
                    ? "checkmark.seal.fill"
                    : "bolt.horizontal.circle"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(
                model.nativeHIDControlConnected
                    ? MouserStyle.connected
                    : .secondary
            )
        }
        .padding(24)
        .frame(maxHeight: 384, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
    }
}

private struct DeviceStatusPill: View {
    let active: Bool
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(active: active)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            (active ? MouserStyle.connected : Color.secondary).opacity(0.10),
            in: Capsule()
        )
        .foregroundStyle(active ? MouserStyle.connected : .secondary)
    }
}

private struct TelemetryItem: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(value))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct QuickControlDock: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                QuickToggleTile(
                    icon: "dial.medium",
                    title: "SmartShift",
                    detail: "滚动时自动切换模式",
                    tint: MouserStyle.accent,
                    isOn: $model.smartShiftEnabled
                )
                QuickToggleTile(
                    icon: "arrow.up.and.down.text.horizontal",
                    title: "反转滚动",
                    detail: "仅作用于外接鼠标",
                    tint: MouserStyle.accentBlue,
                    isOn: $model.invertVerticalScroll
                )
                CurrentProfileTile(
                    name: model.selectedProfile?.name ?? "默认"
                )
            }

            VStack(spacing: 12) {
                QuickToggleTile(
                    icon: "dial.medium",
                    title: "SmartShift",
                    detail: "滚动时自动切换模式",
                    tint: MouserStyle.accent,
                    isOn: $model.smartShiftEnabled
                )
                QuickToggleTile(
                    icon: "arrow.up.and.down.text.horizontal",
                    title: "反转滚动",
                    detail: "仅作用于外接鼠标",
                    tint: MouserStyle.accentBlue,
                    isOn: $model.invertVerticalScroll
                )
                CurrentProfileTile(
                    name: model.selectedProfile?.name ?? "默认"
                )
            }
        }
    }
}

private struct QuickToggleTile: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(isHovered ? 0.34 : 0.12), lineWidth: 0.8)
        }
        .offset(y: isHovered && !reduceMotion ? -3 : 0)
        .shadow(color: tint.opacity(isHovered ? 0.13 : 0.05), radius: 18, y: 8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : MouserMotion.hover, value: isHovered)
    }
}

private struct CurrentProfileTile: View {
    let name: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title3.weight(.medium))
                .foregroundStyle(MouserStyle.warning)
                .frame(width: 42, height: 42)
                .background(MouserStyle.warning.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("当前配置")
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(name))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MouserStyle.warning.opacity(0.12), lineWidth: 0.8)
        }
    }
}

struct MouseImage: View {
    var resourceName: String? = "mx-master-3s"

    var body: some View {
        let resolvedResourceName = resourceName ?? "mx-master-3s"

        if let imageURL = Bundle.main.url(forResource: resolvedResourceName, withExtension: "png"),
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
