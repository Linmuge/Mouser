import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PointerScrollView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsPage(
            title: "指针与滚动",
            subtitle: "调整指针速度、滚轮机械模式和滚动方向。"
        ) {
            NativeDeviceControlSection(model: model)
            PointerSpeedSection(model: model)
            ScrollWheelSection(model: model)
            ScrollDirectionSection(model: model)
        }
    }
}

private struct NativeDeviceControlSection: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsGroup(
            "设备控制",
            caption: model.nativeHIDProbeEnabled
                ? "设置会直接写入鼠标，并在锁屏恢复后自动重放。"
                : "当前只保存到 Mouser 配置；启用原生设备控制后才会直接写入鼠标。"
        ) {
            SettingRow(
                title: "原生 HID++",
                detail: model.localizedRuntime(model.hidppStatusText)
            ) {
                if model.nativeHIDProbeEnabled {
                    Label("已启用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(MouserStyle.connected)
                } else {
                    Button("前往高级设置") {
                        model.selectedSection = .advanced
                    }
                }
            }
        }
    }
}

private struct PointerSpeedSection: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsGroup(
            "指针速度",
            caption: model.formatted(
                "当前设备支持 %@–%@ DPI。",
                String(Int(model.dpiRange.lowerBound)),
                String(Int(model.dpiRange.upperBound))
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("DPI")
                    Spacer()
                    Text("\(Int(model.dpi))")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(MouserStyle.accent)
                }
                Slider(value: $model.dpi, in: model.dpiRange, step: 50)
                HStack {
                    Text("\(Int(model.dpiRange.lowerBound))")
                    Spacer()
                    Text("\(Int(model.dpiRange.upperBound))")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(16)
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 12) {
                Text("DPI 切换预设")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { index in
                        TextField(
                            model.formatted("预设 %@", String(index + 1)),
                            value: Binding(
                                get: {
                                    model.dpiPresets.indices.contains(index)
                                        ? model.dpiPresets[index]
                                        : [800, 1200, 1600, 2400][index]
                                },
                                set: { model.setDPIPreset($0, at: index) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    }
                }
                Text("“循环切换 DPI”动作会按这四档依次切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}

private struct ScrollWheelSection: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsGroup("滚轮", caption: "SmartShift 开启时从棘轮自动切换到飞轮。") {
            SettingRow(title: "SmartShift", detail: "快速滚动时自动进入飞轮") {
                Toggle("SmartShift", isOn: $model.smartShiftEnabled)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "关闭 SmartShift 后", detail: "选择固定的机械滚轮模式") {
                Picker("固定滚轮模式", selection: $model.smartShiftMode) {
                    ForEach(SmartShiftMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(model.smartShiftEnabled)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "切换阈值", detail: "数值越小，越容易切换到飞轮") {
                HStack(spacing: 10) {
                    Slider(value: $model.smartShiftThreshold, in: 1...50, step: 1)
                        .frame(width: 150)
                    Text("\(Int(model.smartShiftThreshold))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                .disabled(!model.smartShiftEnabled)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "棘轮力度", detail: "仅增强版 SmartShift 设备支持") {
                HStack(spacing: 10) {
                    Slider(value: $model.scrollForce, in: 1...100, step: 1)
                        .frame(width: 150)
                    Text("\(Int(model.scrollForce))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

private struct ScrollDirectionSection: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsGroup("滚动方向", caption: "只处理外接鼠标，触控板保持系统设置。") {
            SettingRow(
                title: "反转处理方式",
                detail: model.wheelInversionBackend == .automatic
                    ? "优先写入鼠标固件，锁屏恢复后自动重放"
                    : "保留 HID++ 设备控制，仅由 macOS 辅助功能反转滚动"
            ) {
                Picker("反转处理方式", selection: $model.wheelInversionBackend) {
                    ForEach(WheelInversionBackend.allCases) { backend in
                        Text(LocalizedStringKey(backend.title)).tag(backend)
                    }
                }
                .frame(width: 210)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "反转垂直滚动") {
                Toggle("反转垂直滚动", isOn: $model.invertVerticalScroll)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "反转水平滚动") {
                Toggle("反转水平滚动", isOn: $model.invertHorizontalScroll)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "忽略触控板") {
                Toggle("忽略触控板", isOn: $model.ignoreTrackpad)
            }
            Divider().padding(.leading, 16)
            SettingRow(title: "水平滚轮触发阈值", detail: "数值越小，拇指滚轮动作越灵敏") {
                HStack(spacing: 10) {
                    Slider(value: $model.horizontalScrollThreshold, in: 0.05...1, step: 0.05)
                        .frame(width: 150)
                    Text(model.horizontalScrollThreshold.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }
}

struct HapticsView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsPage(
            title: "触觉反馈",
            subtitle: "控制支持设备的反馈强度和触发时机。"
        ) {
            SettingsGroup("触觉反馈") {
                SettingRow(title: "启用触觉反馈", detail: "仅支持 MX Master 4 等兼容设备") {
                    Toggle("启用触觉反馈", isOn: $model.hapticsEnabled)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "反馈强度") {
                    Picker("反馈强度", selection: $model.hapticStrength) {
                        Text("轻柔").tag(0.0)
                        Text("低").tag(1.0)
                        Text("中").tag(2.0)
                        Text("强").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                }
            }

            SettingsGroup("预览") {
                SettingRow(title: "测试当前强度", detail: "点击后设备会产生一次短促反馈") {
                    Button("播放反馈", systemImage: "waveform") {
                        Task { await model.playHapticPreview() }
                    }
                    .disabled(!model.hapticsEnabled || !model.hapticSupported)
                }
            }

            SettingsGroup(
                "动作反馈",
                caption: "仅为选中的动作播放反馈；编辑、鼠标点击和连续滚动默认保持安静。"
            ) {
                ForEach(Array(WorkspaceModel.hapticEligibleActions.enumerated()), id: \.element) {
                    index, action in
                    SettingRow(title: model.localized(action.title)) {
                        Toggle(
                            model.localized(action.title),
                            isOn: Binding(
                                get: { model.hapticActionIDs.contains(action.rawValue) },
                                set: { model.setHapticEnabled($0, forActionID: action.rawValue) }
                            )
                        )
                    }
                    .disabled(!model.hapticsEnabled)
                    if index < WorkspaceModel.hapticEligibleActions.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }

            SettingsGroup(
                "按键反馈",
                caption: "无论按键执行什么动作，只要选中该物理按键就会播放反馈。"
            ) {
                ForEach(Array(model.availableButtons.enumerated()), id: \.element) { index, button in
                    SettingRow(title: model.localized(button.title), detail: model.localized(button.detail)) {
                        Toggle(
                            model.localized(button.title),
                            isOn: Binding(
                                get: { model.hapticButtonIDs.contains(button.configID) },
                                set: { model.setHapticEnabled($0, forButtonID: button.configID) }
                            )
                        )
                    }
                    .disabled(!model.hapticsEnabled)
                    if index < model.availableButtons.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }

            SettingsGroup("触发策略") {
                SettingRow(
                    title: "防止重复反馈",
                    detail: "100 毫秒内动作与按键同时命中时只播放一次"
                ) {
                    Toggle("防止重复反馈", isOn: $model.hapticDedup)
                }
            }

            if model.forceSensingSupported {
                SettingsGroup("力度感应", caption: "用于 MX Master 4 力度感应按钮的触发阈值。") {
                    SettingRow(
                        title: "触发力度",
                        detail: model.formatted(
                            "设备默认值 %@",
                            String(Int(model.forceSensingDefault))
                        )
                    ) {
                        HStack(spacing: 10) {
                            Slider(
                                value: $model.forceSensitivity,
                                in: model.forceSensingMinimum...model.forceSensingMaximum,
                                step: 1
                            )
                            .frame(width: 180)
                            Text("\(Int(model.forceSensitivity))")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct ActionsRingSettingsView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsPage(
            title: "操作环",
            subtitle: "按住 MX Master 4 感应区并滑向一个方向，释放即可执行。"
        ) {
            SettingsGroup("交互") {
                SettingRow(title: "按住时间", detail: "快速轻按会以可点击模式打开操作环") {
                    HStack(spacing: 10) {
                        Slider(value: $model.actionsRingHoldMilliseconds, in: 100...500, step: 10)
                            .frame(width: 170)
                        Text("\(Int(model.actionsRingHoldMilliseconds)) ms")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "所有应用使用同一组动作") {
                    Toggle("所有应用使用同一组动作", isOn: $model.actionsRingUsesGlobalSlots)
                }
                Divider().padding(.leading, 16)
                SettingRow(
                    title: "切换选区时播放反馈",
                    detail: "需要启用触觉反馈并使用兼容设备"
                ) {
                    Toggle("切换选区时播放反馈", isOn: $model.actionsRingHoverHaptic)
                }
            }

            SettingsGroup(
                "环形动作",
                caption: model.actionsRingUsesGlobalSlots
                    ? "这组动作会用于所有应用配置。"
                    : model.formatted(
                        "正在编辑“%@”的独立操作环。",
                        model.selectedProfile?.name ?? model.localized("默认")
                    )
            ) {
                ForEach(Array(model.actionsRingSlots.indices), id: \.self) { index in
                    SettingRow(
                        title: model.formatted("位置 %@", String(index + 1)),
                        detail: directionLabel(
                            at: index,
                            count: model.actionsRingSlots.count
                        )
                    ) {
                        ActionPicker(
                            title: model.formatted("位置 %@", String(index + 1)),
                            selection: Binding(
                                get: {
                                    guard model.actionsRingSlots.indices.contains(index) else {
                                        return MouserAction.passThrough.rawValue
                                    }
                                    return model.actionsRingSlots[index]
                                },
                                set: { model.setActionsRingSlot($0, at: index) }
                            )
                        )
                        .frame(width: 230)
                    }
                    if index < model.actionsRingSlots.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }

            Label(
                "轻按打开后可点击选区；按住打开后移动拇指并释放。",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func directionLabel(at index: Int, count: Int) -> String {
        guard count == 4 else {
            return model.formatted("顺时针第 %@ 个选区", String(index + 1))
        }
        return model.localized(["上方", "右侧", "下方", "左侧"][index])
    }
}

struct ProfilesView: View {
    @Bindable var model: WorkspaceModel
    @State private var pendingDeleteProfileID: String?

    var body: some View {
        SettingsPage(
            title: "应用配置",
            subtitle: "切换到指定应用时自动应用独立映射。"
        ) {
            SettingsGroup("配置") {
                ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                    HStack(spacing: 8) {
                        Button {
                            model.selectProfile(id: profile.id)
                            model.selectedSection = .buttons
                        } label: {
                            HStack(spacing: 12) {
                                ProfileApplicationIcon(profile: profile, isSelected: profile.id == model.selectedProfileID)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .foregroundStyle(.primary)
                                    Text(profile.bundleID ?? "所有未单独设置的应用")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.selectedProfileID {
                                    Text("当前")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(MouserStyle.accent)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if profile.id != "default" {
                            Button(
                                model.formatted("删除 %@ 配置", profile.name),
                                systemImage: "trash"
                            ) {
                                pendingDeleteProfileID = profile.id
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 14)
                        }
                    }
                    if index < model.profiles.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }

            Button("添加应用配置", systemImage: "plus") {
                chooseApplication()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .alert(
            "删除应用配置？",
            isPresented: Binding(
                get: { pendingDeleteProfileID != nil },
                set: { if !$0 { pendingDeleteProfileID = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeleteProfileID {
                    model.deleteProfile(id: pendingDeleteProfileID)
                }
                pendingDeleteProfileID = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteProfileID = nil
            }
        } message: {
            Text("该应用会重新使用默认按键映射。")
        }
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

private struct ProfileApplicationIcon: View {
    let profile: AppProfile
    let isSelected: Bool

    private var applicationIcon: NSImage? {
        if let path = profile.appIdentifiers.first(where: { $0.hasSuffix(".app") }) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let bundleIdentifier = profile.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return nil
    }

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: profile.systemImage)
                    .font(.title3)
            }
        }
        .foregroundStyle(isSelected ? .white : MouserStyle.accent)
        .frame(width: 36, height: 36)
        .background(
            isSelected ? MouserStyle.accent : MouserStyle.accent.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

struct AdvancedView: View {
    @Bindable var model: WorkspaceModel
    @State private var confirmsUpdateInstall = false

    var body: some View {
        SettingsPage(
            title: "高级",
            subtitle: "启动、更新、诊断和设备识别选项。"
        ) {
            SettingsGroup("外观") {
                SettingRow(title: "界面外观", detail: "默认随 macOS 自动切换") {
                    Picker("界面外观", selection: $model.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.title)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "界面语言", detail: "立即应用到窗口和菜单栏") {
                    Picker("界面语言", selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .frame(width: 180)
                }
                Divider().padding(.leading, 16)
                SettingRow(
                    title: "鼠标示意图",
                    detail: "识别错误时手动纠正外观；不会改变真实设备能力"
                ) {
                    Picker(
                        "鼠标示意图",
                        selection: Binding(
                            get: { model.deviceLayoutOverrideKey },
                            set: { model.setDeviceLayoutOverride($0) }
                        )
                    ) {
                        ForEach(LogitechDeviceCatalog.manualLayoutChoices) { choice in
                            Text(LocalizedStringKey(choice.title)).tag(choice.key)
                        }
                    }
                    .frame(width: 180)
                }
            }

            SettingsGroup("手势识别", caption: "这些参数同时用于系统事件和 HID++ RawXY 手势。") {
                SettingRow(title: "触发距离", detail: "数值越小越灵敏") {
                    HStack(spacing: 10) {
                        Slider(value: $model.gestureThreshold, in: 15...100, step: 1)
                            .frame(width: 150)
                        Text("\(Int(model.gestureThreshold)) px")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "识别窗口", detail: "完成一次方向动作的最长时间") {
                    HStack(spacing: 10) {
                        Slider(value: $model.gestureCommitWindowMilliseconds, in: 150...800, step: 10)
                            .frame(width: 150)
                        Text("\(Int(model.gestureCommitWindowMilliseconds)) ms")
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "转向停顿", detail: "停顿后允许识别新的方向") {
                    HStack(spacing: 10) {
                        Slider(value: $model.gestureSettleMilliseconds, in: 40...250, step: 5)
                            .frame(width: 150)
                        Text("\(Int(model.gestureSettleMilliseconds)) ms")
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "斜向容差", detail: "越小越严格排除斜向移动") {
                    HStack(spacing: 10) {
                        Slider(value: $model.gestureCrossRatio, in: 0.15...1.0, step: 0.05)
                            .frame(width: 150)
                        Text(model.gestureCrossRatio.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            SettingsGroup("启动") {
                SettingRow(
                    title: "登录时启动 Mouser",
                    detail: model.localizedRuntime(model.loginItemStatusText)
                ) {
                    Toggle(
                        "登录时启动 Mouser",
                        isOn: Binding(
                            get: { model.startAtLogin },
                            set: { model.setStartAtLogin($0) }
                        )
                    )
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "启动后隐藏窗口", detail: "Mouser 仍会在菜单栏中运行") {
                    Toggle("启动后隐藏窗口", isOn: $model.startMinimized)
                }
            }

            SettingsGroup(
                "原生滚轮引擎",
                caption: "手动切换到纯 macOS 事件模式；通常保持关闭，并在滚动方向中选择自动或 macOS 回退。"
            ) {
                SettingRow(
                    title: "启用原生事件处理",
                    detail: model.localizedRuntime(model.eventTapStatusText)
                ) {
                    Toggle(
                        "启用原生事件处理",
                        isOn: Binding(
                            get: { model.nativeEventTapEnabled },
                            set: { model.setNativeEventTapEnabled($0) }
                        )
                    )
                }
            }

            SettingsGroup(
                "原生 HID++",
                caption: "正式版默认启用，直接读取和写入 Logitech 鼠标，并在锁屏恢复后重新连接和应用设置。"
            ) {
                SettingRow(
                    title: "启用原生设备控制",
                    detail: model.localizedRuntime(model.hidppStatusText)
                ) {
                    Toggle(
                        "启用原生设备控制",
                        isOn: Binding(
                            get: { model.nativeHIDProbeEnabled },
                            set: { model.setNativeHIDProbeEnabled($0) }
                        )
                    )
                }
            }

            SettingsGroup(
                "开发者诊断",
                caption: "仅在排查按键、手势或锁屏恢复问题时开启；日志只保存在内存中。"
            ) {
                SettingRow(title: "记录调试事件", detail: "最多保留最近 200 行") {
                    Toggle("记录调试事件", isOn: $model.debugMode)
                }
                if model.debugMode {
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("事件日志")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button("清空") { model.clearDebugLog() }
                            Button("导出…") { model.exportDebugLog() }
                        }
                        ScrollView([.horizontal, .vertical]) {
                            Text(model.debugLogText.isEmpty ? "等待事件…" : model.debugLogText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 130)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(16)

                    Divider().padding(.leading, 16)
                    SettingRow(title: "录制 HID++ 手势", detail: "记录按下、RawXY 位移和释放") {
                        Toggle(
                            "录制 HID++ 手势",
                            isOn: Binding(
                                get: { model.gestureRecording },
                                set: { model.setGestureRecording($0) }
                            )
                        )
                    }
                    if model.gestureRecording || !model.gestureRecords.isEmpty {
                        Divider().padding(.leading, 16)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("手势记录")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button("清空") { model.clearGestureRecords() }
                            }
                            ScrollView([.horizontal, .vertical]) {
                                Text(
                                    model.gestureRecordsText.isEmpty
                                        ? "按住已映射的手势按钮并移动鼠标…"
                                        : model.gestureRecordsText
                                )
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 100)
                            .padding(10)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(16)
                    }
                }
            }

            SettingsGroup("维护") {
                SettingRow(
                    title: "截图保存位置",
                    detail: model.localizedRuntime(model.screenshotStatusText)
                ) {
                    HStack {
                        Button("选择…") {
                            chooseScreenshotDirectory()
                        }
                        if model.hasCustomScreenshotDirectory {
                            Button("使用系统默认") {
                                model.resetScreenshotDirectory()
                            }
                        }
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(
                    title: "自动检查更新",
                    detail: model.localizedRuntime(model.updateStatusText)
                ) {
                    Toggle("自动检查更新", isOn: $model.automaticallyChecksForUpdates)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "更新", detail: "更新源：Linmuge/Mouser") {
                    HStack {
                        Button("检查更新") {
                            Task { await model.checkForUpdates() }
                        }
                        .disabled(model.updateState == .checking)
                        if model.latestReleaseURL != nil {
                            if model.canInstallLatestRelease {
                                Button("下载并安装") {
                                    confirmsUpdateInstall = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Button("打开下载页") {
                                model.openLatestRelease()
                            }
                        }
                    }
                }
                if !model.updateInstallStatusText.isEmpty {
                    Divider().padding(.leading, 16)
                    SettingRow(
                        title: "安装状态",
                        detail: model.localizedRuntime(model.updateInstallStatusText)
                    ) {
                        if model.updateInstallInProgress {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "诊断信息", detail: "不包含配置内容、账户或凭据") {
                    Button("导出…") {
                        model.exportDiagnostics()
                    }
                }
            }

            SettingsGroup("关于") {
                SettingRow(title: "Mouser", detail: "Forked from TomBadash/Mouser · 感谢原作者 Tom Badash") {
                    Text(model.formatted("v%@ Swift 原生版", model.currentVersion))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(
            "安装 Mouser 更新？",
            isPresented: $confirmsUpdateInstall,
            titleVisibility: .visible
        ) {
            Button("下载、验证并安装") {
                Task { await model.downloadAndInstallLatestUpdate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Mouser 会验证 DMG 摘要、代码签名和 Gatekeeper，然后退出、替换应用并自动重新打开。")
        }
    }

    private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择截图保存文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if model.hasCustomScreenshotDirectory {
            panel.directoryURL = URL(
                filePath: model.screenshotDirectory,
                directoryHint: .isDirectory
            )
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Pictures", directoryHint: .isDirectory)
        }
        guard panel.runModal() == .OK else { return }
        model.setScreenshotDirectory(panel.url)
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: title, subtitle: subtitle)
                content
                    .mouserReveal(delay: 0.04)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
