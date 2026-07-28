import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrecisionOverviewInspector: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        PrecisionInspectorPanel(title: "准备就绪", badge: "D01") {
            PrecisionSectionGap()
            PrecisionSettingRow("SmartShift", detail: "快速滚动切换飞轮") {
                PrecisionSwitch(isOn: $model.smartShiftEnabled)
            }
            PrecisionSettingRow("垂直滚动反转", detail: "当前配置") {
                PrecisionSwitch(isOn: $model.invertVerticalScroll)
            }
            PrecisionSectionGap()
            PrecisionFieldLabel("恢复状态")
            PrecisionInputField(value: model.configurationLoaded ? "已恢复" : "恢复中", trailing: "status")
        }
    }
}

struct PrecisionButtonsInspector: View {
    @Bindable var model: WorkspaceModel
    @State private var longPressEnabled = false

    private var selectedActionID: Binding<String> {
        Binding(
            get: { model.mapping(for: model.selectedButton)?.actionID ?? MouserAction.passThrough.rawValue },
            set: { model.setActionID($0, for: model.selectedButton) }
        )
    }

    var body: some View {
        PrecisionInspectorPanel(title: model.localized(model.selectedButton.title), badge: buttonCode) {
            PrecisionFieldLabel("按下时执行")
                .padding(.top, 20)
            PrecisionActionField(
                selection: selectedActionID,
                includesGestureSwipe: model.selectedButton.supportsSlideGesture
            )
            PrecisionSettingRow(
                "长按动作",
                detail: "500 毫秒后触发"
            ) {
                PrecisionSwitch(isOn: $longPressEnabled)
            }
            PrecisionFieldLabel("当前配置")
                .padding(.top, 16)
            PrecisionInputField(
                value: model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"),
                trailing: "独立保存"
            )
        }
    }

    private var buttonCode: String {
        switch model.selectedButton {
        case .middle: "B03"
        case .back: "B04"
        case .forward: "B05"
        case .gesture: "B06"
        case .modeShift: "B07"
        default: "B01"
        }
    }
}

struct PrecisionPointerInspector: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        PrecisionInspectorPanel(title: "精确控制", badge: "P01") {
            PrecisionRangeRow(
                label: "指针速度",
                valueText: "\(Int(model.dpi)) DPI",
                value: $model.dpi,
                range: model.dpiRange,
                step: 50
            )
            .padding(.top, 14)
            PrecisionSettingRow(
                "SmartShift",
                detail: "快速滚动切换飞轮"
            ) {
                PrecisionSwitch(isOn: $model.smartShiftEnabled)
            }
            .padding(.top, 14)
            PrecisionFieldLabel("关闭 SmartShift 后")
                .padding(.top, 8)
            PrecisionSegmentedControl(
                first: "棘轮",
                second: "飞轮",
                isSecond: Binding(
                    get: { model.smartShiftMode == .freeSpin },
                    set: { model.smartShiftMode = $0 ? .freeSpin : .ratchet }
                )
            )
            PrecisionSettingRow(
                "垂直滚动反转",
                detail: "不影响触控板"
            ) {
                PrecisionSwitch(isOn: $model.invertVerticalScroll)
            }
            .padding(.top, 24)
            PrecisionSettingRow(
                "水平滚动反转",
                detail: "侧滚轮"
            ) {
                PrecisionSwitch(isOn: $model.invertHorizontalScroll)
            }
            .padding(.top, 4)
        }
    }
}

struct PrecisionHapticsInspector: View {
    @Bindable var model: WorkspaceModel

    private var strengthPercent: Binding<Double> {
        Binding(
            get: { model.hapticStrength / 3 * 100 },
            set: { model.hapticStrength = min(3, max(0, $0 / 100 * 3)) }
        )
    }

    var body: some View {
        PrecisionInspectorPanel(title: "强度设置", badge: "H01") {
            PrecisionSectionGap()
            PrecisionSettingRow("启用触觉反馈", detail: "需要兼容设备") {
                PrecisionSwitch(isOn: $model.hapticsEnabled)
            }
            PrecisionRangeRow(
                label: "反馈强度",
                valueText: "\(Int(strengthPercent.wrappedValue))%",
                value: strengthPercent,
                range: 0...100,
                step: 1
            )
            Button {
                Task { await model.playHapticPreview() }
            } label: {
                HStack {
                    Text("测试反馈")
                    Spacer()
                    Text("播放").foregroundStyle(MouserStyle.muted)
                }
            }
            .buttonStyle(PrecisionFieldButtonStyle())
            .disabled(!model.hapticsEnabled)
            PrecisionSectionGap()
            PrecisionSettingRow("按键反馈", detail: "按键触发") {
                PrecisionSwitch(isOn: hapticButtonBinding)
            }
            PrecisionSettingRow("动作反馈", detail: "动作触发") {
                PrecisionSwitch(isOn: hapticActionBinding)
            }
            PrecisionSettingRow("避免重复", detail: "100 毫秒内一次") {
                PrecisionSwitch(isOn: $model.hapticDedup)
            }
        }
    }

    private var hapticButtonBinding: Binding<Bool> {
        Binding(
            get: { model.hapticButtonIDs.contains(model.selectedButton.configID) },
            set: { model.setHapticEnabled($0, forButtonID: model.selectedButton.configID) }
        )
    }

    private var hapticActionBinding: Binding<Bool> {
        Binding(
            get: { model.hapticActionIDs.contains(MouserAction.switchScrollMode.rawValue) },
            set: { model.setHapticEnabled($0, forActionID: MouserAction.switchScrollMode.rawValue) }
        )
    }
}

struct PrecisionActionsRingInspector: View {
    @Bindable var model: WorkspaceModel

    private var selectedAction: Binding<String> {
        Binding(
            get: {
                let slots = model.actionsRingSlots
                guard slots.indices.contains(model.selectedActionsRingIndex) else {
                    return MouserAction.passThrough.rawValue
                }
                return slots[model.selectedActionsRingIndex]
            },
            set: { model.setActionsRingSlot($0, at: model.selectedActionsRingIndex) }
        )
    }

    var body: some View {
        PrecisionInspectorPanel(title: actionTitle, badge: "R04") {
            PrecisionSectionGap()
            PrecisionFieldLabel("当前方向动作")
            PrecisionActionField(selection: selectedAction)
            PrecisionSectionGap()
            PrecisionFieldLabel("作用范围")
            PrecisionSegmentedControl(
                first: "当前应用",
                second: "全部应用",
                isSecond: $model.actionsRingUsesGlobalSlots
            )
            PrecisionRangeRow(
                label: "按住延迟",
                valueText: "\(Int(model.actionsRingHoldMilliseconds)) ms",
                value: $model.actionsRingHoldMilliseconds,
                range: 100...500,
                step: 10
            )
            PrecisionSectionGap()
            PrecisionSettingRow("悬停触觉", detail: "经过扇区时反馈") {
                PrecisionSwitch(isOn: $model.actionsRingHoverHaptic)
            }
        }
    }

    private var actionTitle: String {
        model.localized(MouserAction(rawValue: selectedAction.wrappedValue)?.title ?? "无动作")
    }
}

struct PrecisionProfilesInspector: View {
    @Bindable var model: WorkspaceModel
    @State private var automaticallySwitches = true
    @State private var inheritsPointerSettings = false

    var body: some View {
        PrecisionInspectorPanel(
            title: model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"),
            badge: "A01"
        ) {
            PrecisionSectionGap()
            PrecisionFieldLabel("适用应用")
            PrecisionInputField(value: applicableApplication, trailing: "chevron")
            PrecisionSectionGap()
            PrecisionSettingRow("自动切换", detail: "应用进入前台时") {
                PrecisionSwitch(isOn: $automaticallySwitches)
            }
            PrecisionSettingRow("继承指针设置", detail: "使用默认配置") {
                PrecisionSwitch(isOn: $inheritsPointerSettings)
            }
            PrecisionSectionGap()
            Button(action: chooseApplication) {
                HStack {
                    Text("添加应用配置")
                    Spacer()
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(PrecisionFieldButtonStyle())
        }
    }

    private var applicableApplication: String {
        guard let profile = model.selectedProfile, profile.id != "default" else { return "未指定应用" }
        return profile.name
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "添加配置"
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let candidate = ApplicationProfileCandidate(applicationURL: url)
        else { return }
        _ = model.addApplicationProfile(candidate)
    }
}

struct PrecisionAdvancedInspector: View {
    @Bindable var model: WorkspaceModel
    @State private var restoresAfterWake = true
    @State private var restoresAfterReconnect = true

    var body: some View {
        PrecisionInspectorPanel(title: "系统与恢复", badge: "S01") {
            PrecisionSectionGap()
            PrecisionSettingRow("登录时启动", detail: "保持设备连接") {
                PrecisionSwitch(isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
            }
            PrecisionSettingRow("唤醒后恢复", detail: "DPI、滚轮和方向") {
                PrecisionSwitch(isOn: $restoresAfterWake)
            }
            PrecisionSettingRow("重连后恢复", detail: "恢复当前配置") {
                PrecisionSwitch(isOn: $restoresAfterReconnect)
            }
            PrecisionSectionGap()
            PrecisionFieldLabel("更新")
            Button {
                Task { await model.checkForUpdates() }
            } label: {
                HStack {
                    Text("检查更新")
                    Spacer()
                    Text(model.currentVersion).foregroundStyle(MouserStyle.muted)
                }
            }
            .buttonStyle(PrecisionFieldButtonStyle())
            .disabled(model.updateState == .checking)
            PrecisionSectionGap()
            PrecisionSettingRow("诊断日志", detail: "仅排查问题时开启") {
                PrecisionSwitch(isOn: $model.debugMode)
            }
        }
    }
}

private struct PrecisionInspectorPanel<Content: View>: View {
    let title: String
    let badge: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        badge: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(LocalizedStringKey(title))
                            .font(.system(size: 23, weight: .bold))
                            .tracking(-0.55)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(badge)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MouserStyle.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .overlay { Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1) }
                    }
                    content
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 20)
            }

            HStack(spacing: 7) {
                Circle().fill(MouserStyle.connected).frame(width: 7, height: 7)
                Text("已自动保存")
            }
            .font(.system(size: 12))
            .foregroundStyle(MouserStyle.connected)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 13)
            .padding(.horizontal, 22)
            .padding(.bottom, 17)
        }
        .background(panelColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.13), radius: 30, y: 18)
    }

    private var panelColor: Color {
        colorScheme == .dark
            ? Color(red: 27 / 255, green: 36 / 255, blue: 37 / 255)
            : Color.white.opacity(0.88)
    }
}

private struct PrecisionSectionGap: View {
    var body: some View {
        Color.clear.frame(height: 26)
    }
}

private struct PrecisionFieldLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 12))
            .foregroundStyle(MouserStyle.muted)
            .padding(.bottom, 8)
    }
}

private struct PrecisionSettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .semibold))
                Text(LocalizedStringKey(detail)).font(.system(size: 12)).foregroundStyle(MouserStyle.muted)
            }
            Spacer(minLength: 6)
            control
        }
        .frame(minHeight: 58)
    }
}

private struct PrecisionSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? MouserStyle.accent : Color.secondary.opacity(0.24))
                .frame(width: 42, height: 24)
                .overlay {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .offset(x: isOn ? 9 : -9)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
        .accessibilityLabel(isOn ? "开启" : "关闭")
        .accessibilityValue(isOn ? "开启" : "关闭")
    }
}

private struct PrecisionInputField: View {
    let value: String
    let trailing: String
    var body: some View {
        HStack {
            Text(LocalizedStringKey(value)).lineLimit(1)
            Spacer()
            if trailing == "status" {
                Circle().fill(MouserStyle.connected).frame(width: 7, height: 7)
            } else if trailing == "chevron" {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(MouserStyle.muted)
            } else {
                Text(trailing).font(.system(size: 12)).foregroundStyle(MouserStyle.muted)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1) }
    }
}

private struct PrecisionActionField: View {
    @Binding var selection: String
    var includesGestureSwipe = false

    var body: some View {
        ZStack {
            PrecisionActionFieldVisualLabel(title: displayTitle)
            ActionPicker(
                title: "动作",
                selection: $selection,
                includesGestureSwipe: includesGestureSwipe
            )
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(0.001)
        }
        .frame(height: 44)
    }

    private var displayTitle: String {
        if selection == "gesture_swipe" { return "打开 Actions Ring" }
        if let shortcut = CustomShortcut(actionID: selection) { return shortcut.displayText }
        return MouserAction(rawValue: selection)?.title ?? "无动作"
    }
}

private struct PrecisionActionFieldVisualLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(MouserStyle.muted)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PrecisionRangeRow: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private var quantizedValue: Binding<Double> {
        Binding(
            get: { value },
            set: {
                value = PrecisionRangeQuantizer.quantize(
                    $0,
                    step: step,
                    range: range
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(LocalizedStringKey(label)).foregroundStyle(MouserStyle.muted)
                Spacer()
                Text(valueText).fontWeight(.bold).monospacedDigit()
            }
            .font(.system(size: 12))
            Slider(value: quantizedValue, in: range)
                .controlSize(.small)
        }
        .padding(.vertical, 14)
    }
}

enum PrecisionRangeQuantizer {
    static func quantize(
        _ proposedValue: Double,
        step: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let clamped = min(max(proposedValue, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }

        let offset = clamped - range.lowerBound
        let quantized = range.lowerBound + (offset / step).rounded() * step
        return min(max(quantized, range.lowerBound), range.upperBound)
    }
}

private struct PrecisionSegmentedControl: View {
    let first: String
    let second: String
    @Binding var isSecond: Bool

    var body: some View {
        HStack(spacing: 3) {
            segment(first, selected: !isSecond) { isSecond = false }
            segment(second, selected: isSecond) { isSecond = true }
        }
        .padding(3)
        .frame(height: 34)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: selected ? .bold : .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: selected ? .black.opacity(0.11) : .clear, radius: 2, y: 1)
        }.buttonStyle(.plain)
    }
}

private struct PrecisionFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(MouserStyle.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.primary.opacity(configuration.isPressed ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1) }
    }
}
