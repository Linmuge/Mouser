import SwiftUI

/// FundBar 式仪表盘：英雄卡 + 左列功能面板 + 右侧状态栏，无页面标题。
struct OverviewView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !model.accessibilityGranted {
                    AccessibilityBanner(model: model)
                        .mouserReveal(delay: 0.02)
                }

                DeviceHeroPanel(model: model)
                    .mouserReveal(delay: 0.04)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        dashboardMainColumn
                        GlassEffectContainer(spacing: 12) {
                            dashboardRail
                        }
                        .frame(width: 288)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        dashboardMainColumn
                        GlassEffectContainer(spacing: 12) {
                            dashboardRail
                        }
                    }
                }
                .mouserReveal(delay: 0.09)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var dashboardMainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            ButtonMappingPanel(model: model)
            WheelPointerCard(model: model)
            HapticsCard(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dashboardRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceStatusPanel(model: model)
            ActionsRingPanel(model: model)
            QuickSettingsPanel(model: model)

            HStack(spacing: 6) {
                Image(
                    systemName: model.nativeHIDControlConnected
                        ? "checkmark.seal.fill"
                        : "bolt.horizontal.circle"
                )
                Text(model.nativeHIDControlConnected ? "原生控制在线" : "等待原生控制")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(
                model.nativeHIDControlConnected ? MouserStyle.connected : .secondary
            )
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(persistenceStatusColor ?? Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(model.configurationLoaded ? "原生配置已接通" : "原生迁移中")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(
                    model.localizedRuntime(
                        model.configurationPersistenceState.message
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            }
            .padding(.horizontal, 4)
            .animation(MouserMotion.selection, value: model.configurationPersistenceState)
        }
    }

    private var persistenceStatusColor: Color? {
        switch model.configurationPersistenceState {
        case .saved, .recovered: MouserStyle.connected
        case .saving: MouserStyle.warning
        case .failed: .red
        case .loading, .preview: nil
        }
    }
}

// MARK: - 权限引导

private struct AccessibilityBanner: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(MouserStyle.warning)
                .frame(width: 38, height: 38)
                .background(
                    MouserStyle.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: MouserStyle.radiusControl, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("需要辅助功能权限")
                    .font(.system(size: 13, weight: .semibold))
                Text("允许后 Mouser 才能监听鼠标按键和调整滚轮方向。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("请求权限") {
                model.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(14)
        .mouserCard(tint: MouserStyle.warning)
    }
}

// MARK: - 英雄卡

private struct DeviceHeroPanel: View {
    @Bindable var model: WorkspaceModel

    private var statusTint: Color {
        model.mouseConnected || model.receiverDetected
            ? MouserStyle.connected
            : MouserStyle.warning
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        MouserIconBadge(
                            systemImage: model.mouseConnected
                                ? "computermouse.fill"
                                : "computermouse",
                            size: 30
                        )
                        Text(model.localizedRuntime(model.deviceName))
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                        StatusPill(
                            title: model.localizedRuntime(model.deviceStatusText),
                            tint: statusTint,
                            active: model.mouseConnected || model.receiverDetected
                        )
                    }
                    Text(heroCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 40)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(model.dpi))")
                            .font(.system(size: 44, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(MouserMotion.numeric, value: model.dpi)
                        Text("DPI")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    DPIRangeBar(model: model)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)

            DeviceArtwork(resourceName: model.deviceProfile.imageResource)
                .frame(width: 290, height: 220)
                .padding(.trailing, 10)
        }
        .frame(minHeight: 232)
        .mouserCard(cornerRadius: MouserStyle.radiusPanel, tint: statusTint)
        .mouserHoverLift()
    }

    private var heroCaption: String {
        model.deviceTransport == "—"
            ? "等待 Logitech 设备接入"
            : model.localizedRuntime(model.deviceTransport)
    }
}

/// DPI 量程条：当前位置 + 四档预设刻度，全部来自真实设备数据。
struct DPIRangeBar: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let usable = max(proxy.size.width - 9, 1)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 6)

                    Capsule()
                        .fill(MouserStyle.accent.opacity(0.7))
                        .frame(height: 6)
                        .frame(width: 9 + progressRatio * usable)

                    ForEach(0..<model.dpiPresets.count, id: \.self) { index in
                        if model.dpiPresets.indices.contains(index) {
                            Circle()
                                .fill(Color.primary.opacity(0.18))
                                .frame(width: 3, height: 3)
                                .position(
                                    x: 4.5 + normalized(model.dpiPresets[index]) * usable,
                                    y: 15
                                )
                                .accessibilityHidden(true)
                        }
                    }

                    Circle()
                        .fill(MouserStyle.accent)
                        .frame(width: 9, height: 9)
                        .position(x: 4.5 + progressRatio * usable, y: 3)
                        .shadow(color: MouserStyle.accent.opacity(0.45), radius: 4)
                }
            }
            .frame(height: 18)

            HStack {
                Text("\(Int(model.dpiRange.lowerBound))")
                Spacer()
                Text("\(Int(model.dpiRange.upperBound))")
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }

    private var progressRatio: CGFloat {
        let range = model.dpiRange
        guard range.upperBound > range.lowerBound else { return 0 }
        return CGFloat(
            min(max((model.dpi - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        )
    }

    private func normalized(_ value: Int) -> CGFloat {
        let range = model.dpiRange
        guard range.upperBound > range.lowerBound else { return 0 }
        return CGFloat(
            min(
                max(
                    Double(value - Int(range.lowerBound))
                        / Double(Int(range.upperBound) - Int(range.lowerBound)),
                    0
                ),
                1
            )
        )
    }
}

private struct DeviceArtwork: View {
    let resourceName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var hoverOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            MouseImage(resourceName: resourceName)
                .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
                .rotation3DEffect(
                    .degrees(Double(-hoverOffset.height) * 0.2),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(Double(hoverOffset.width) * 0.2),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .offset(hoverOffset)
                .shadow(
                    color: .black.opacity(isHovered ? 0.22 : 0.16),
                    radius: isHovered ? 24 : 18,
                    y: isHovered ? 14 : 11
                )
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
                    width: (location.x / width - 0.5) * 12,
                    height: (location.y / height - 0.5) * 9
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

// MARK: - 左列功能面板

private struct WheelPointerCard: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        DashboardPanel(
            title: "滚轮与指针",
            onEdit: { model.selectedSection = .pointerAndScroll }
        ) {
            quickRow(
                icon: "dial.medium",
                title: "SmartShift",
                detail: "滚动时自动切换模式",
                bounce: model.smartShiftEnabled
            ) {
                Toggle("SmartShift", isOn: $model.smartShiftEnabled)
            }
            MouserHairline()
            quickRow(
                icon: "arrow.up.and.down.text.horizontal",
                title: "反转滚动",
                detail: "仅作用于外接鼠标",
                bounce: model.invertVerticalScroll
            ) {
                Toggle("反转滚动", isOn: $model.invertVerticalScroll)
            }
            MouserHairline()
            quickRow(
                icon: "cursorarrow.and.square.on.square.dashed",
                title: "忽略触控板",
                detail: "滚动方向调整只处理外接鼠标"
            ) {
                Toggle("忽略触控板", isOn: $model.ignoreTrackpad)
            }
        }
    }
}

private struct HapticsCard: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        DashboardPanel(
            title: model.localized("触觉反馈"),
            onEdit: { model.selectedSection = .haptics }
        ) {
            quickRow(
                icon: "waveform",
                title: "启用触觉反馈",
                detail: "仅支持 MX Master 4 等兼容设备",
                bounce: model.hapticsEnabled
            ) {
                Toggle("启用触觉反馈", isOn: $model.hapticsEnabled)
            }
            MouserHairline()
            quickRow(
                icon: "waveform.path.ecg",
                title: "反馈强度",
                detail: model.hapticSupported ? "" : "当前设备不支持"
            ) {
                Picker("反馈强度", selection: $model.hapticStrength) {
                    Text("轻柔").tag(0.0)
                    Text("低").tag(1.0)
                    Text("中").tag(2.0)
                    Text("强").tag(3.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .disabled(!model.hapticsEnabled)
            }
        }
    }
}

/// 仪表盘面板：卡片标题（15pt semibold）+ 右上「编辑」入口 + 内容行。
struct DashboardPanel<Content: View>: View {
    let title: String
    let onEdit: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        onEdit: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onEdit = onEdit
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onEdit) {
                    HStack(spacing: 5) {
                        Text("编辑")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MouserStyle.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            content
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserCard(cornerRadius: MouserStyle.radiusCard)
    }
}

private func quickRow<Control: View>(
    icon: String,
    title: String,
    detail: String,
    bounce: Bool? = nil,
    @ViewBuilder control: () -> Control
) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MouserStyle.accent)
            .frame(width: 32, height: 32)
            .background(
                MouserStyle.accent.opacity(0.10),
                in: RoundedRectangle(cornerRadius: MouserStyle.radiusControl, style: .continuous)
            )
            .modifier(BounceWhenChanged(value: bounce))
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .semibold))
            if !detail.isEmpty {
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 10)
        control()
            .labelsHidden()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minHeight: 52)
}

/// 开关切换时图标轻弹一下，给玻璃面板一点生命感。
private struct BounceWhenChanged: ViewModifier {
    let value: Bool?

    func body(content: Content) -> some View {
        if let value {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

// MARK: - 右侧状态栏

private struct DeviceStatusPanel: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railTitle("设备状态")
            statusRow(
                label: "电量",
                value: model.localizedRuntime(model.batteryStatusText),
                tint: MouserStyle.connected
            )
            railHairline()
            statusRow(
                label: "滚轮",
                value: model.localizedRuntime(model.scrollModeText),
                tint: MouserStyle.accent
            )
            railHairline()
            statusRow(
                label: "连接",
                value: model.deviceTransport == "—"
                    ? model.localized("等待设备")
                    : model.localizedRuntime(model.deviceTransport),
                tint: MouserStyle.accent
            )
            railHairline()
            statusRow(
                label: "DPI",
                value: "\(Int(model.dpi))",
                tint: MouserStyle.accent
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserCard(cornerRadius: MouserStyle.radiusCard)
    }
}

private struct ActionsRingPanel: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railTitle(model.localized("操作环"))
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MouserStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        MouserStyle.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: MouserStyle.radiusControl, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.formatted("%@ 个选区", String(model.actionsRingSlots.count)))
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.actionsRingUsesGlobalSlots ? "所有应用共用" : "每个应用配置独立")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    model.selectedSection = .actionsRing
                } label: {
                    HStack(spacing: 5) {
                        Text("编辑")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MouserStyle.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserCard(cornerRadius: MouserStyle.radiusCard)
    }
}

private struct QuickSettingsPanel: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railTitle("快速设置")

            Button {
                model.selectedSection = .profiles
            } label: {
                HStack(spacing: 8) {
                    Text("当前配置")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            railHairline()

            railToggle("登录时启动 Mouser") {
                Toggle(
                    "登录时启动 Mouser",
                    isOn: Binding(
                        get: { model.startAtLogin },
                        set: { model.setStartAtLogin($0) }
                    )
                )
            }
            railHairline()
            railToggle("自动检查更新") {
                Toggle("自动检查更新", isOn: $model.automaticallyChecksForUpdates)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserCard(cornerRadius: MouserStyle.radiusCard)
    }
}

private func railTitle(_ title: String) -> some View {
    Text(LocalizedStringKey(title))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
}

private func railHairline() -> some View {
    Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 0.5)
        .padding(.vertical, 3)
}

private func railToggle(_ title: String, @ViewBuilder control: () -> some View) -> some View {
    HStack {
        Text(LocalizedStringKey(title))
            .font(.system(size: 12))
        Spacer(minLength: 8)
        control()
            .labelsHidden()
    }
    .padding(.horizontal, 2)
    .padding(.vertical, 5)
}

private func statusRow(label: String, value: String, tint: Color) -> some View {
    HStack(spacing: 10) {
        Text(LocalizedStringKey(label))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Spacer(minLength: 8)
        Text(LocalizedStringKey(value))
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
    }
    .padding(.vertical, 5)
}

// MARK: - 共享

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
