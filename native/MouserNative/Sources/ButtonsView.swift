import SwiftUI

// MARK: - 仪表盘上的按键面板（图 + 热点 + 当前映射清单）

struct ButtonMappingPanel: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("当前按键映射")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    model.selectedSection = .buttons
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
                .help("按键映射")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    MouseButtonStage(model: model)
                        .frame(width: 250)
                    buttonList
                }

                VStack(alignment: .leading, spacing: 0) {
                    MouseButtonStage(model: model)
                        .frame(height: 250)
                    buttonList
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserCard(cornerRadius: MouserStyle.radiusCard)
    }

    @ViewBuilder
    private var buttonList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("按键")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("当前动作")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            MouserHairline()

            ForEach(Array(model.availableButtons.enumerated()), id: \.element) { index, button in
                Button {
                    withAnimation(reduceMotion ? nil : MouserMotion.selection) {
                        model.selectedButton = button
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: button == model.selectedButton ? "record.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(
                                button == model.selectedButton
                                    ? AnyShapeStyle(MouserStyle.accent)
                                    : AnyShapeStyle(.tertiary)
                            )
                            .frame(width: 18)
                        Text(LocalizedStringKey(button.title))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 10)
                        Text(
                            model.localizedRuntime(
                                model.mapping(for: button)?.actionTitle ?? "未设置"
                            )
                        )
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < model.availableButtons.count - 1 {
                    MouserHairline()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 滑入层：按键编辑

struct ButtonsDetailContent: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(
                "正在编辑",
                caption: model.localized(model.selectedButton.detail)
            ) {
                ButtonEditorRow(model: model)
                MouserHairline()
                buttonPickerRow
            }

            HorizontalScrollMappingsSection(model: model)

            SettingsGroup("全部按键", caption: "点击一行切换正在编辑的按键。") {
                ForEach(Array(model.availableButtons.enumerated()), id: \.element) { index, button in
                    Button {
                        withAnimation(MouserMotion.selection) {
                            model.selectedButton = button
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: button == model.selectedButton ? "record.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    button == model.selectedButton
                                        ? AnyShapeStyle(MouserStyle.accent)
                                        : AnyShapeStyle(.tertiary)
                                )
                                .frame(width: 18)
                            Text(LocalizedStringKey(button.title))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(
                                model.localizedRuntime(
                                    model.mapping(for: button)?.actionTitle ?? "未设置"
                                )
                            )
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < model.availableButtons.count - 1 {
                        MouserHairline()
                    }
                }
            }

            Label("更改会自动保存", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(MouserStyle.connected)
        }
    }

    @ViewBuilder
    private var buttonPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按下时执行")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            ActionPicker(
                title: "动作",
                selection: selectedActionID,
                includesGestureSwipe: model.selectedButton.supportsSlideGesture
            )
            .controlSize(.large)
            .frame(maxWidth: 260, alignment: .leading)

            if selectedActionID.wrappedValue == "gesture_swipe" {
                GestureMappingEditor(model: model, button: model.selectedButton)
            } else if selectedActionID.wrappedValue == MouserAction.paste.rawValue {
                LabeledContent("发送快捷键") {
                    Text("⌘V")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            .quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedActionID: Binding<String> {
        Binding(
            get: {
                model.mapping(for: model.selectedButton)?.actionID
                    ?? MouserAction.passThrough.rawValue
            },
            set: { model.setActionID($0, for: model.selectedButton) }
        )
    }
}

/// 正在编辑的按键选择行。
private struct ButtonEditorRow: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.availableButtons) { button in
                    Button {
                        withAnimation(MouserMotion.selection) {
                            model.selectedButton = button
                        }
                    } label: {
                        Text(LocalizedStringKey(button.title))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                button == model.selectedButton ? .white : .primary
                            )
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                button == model.selectedButton
                                    ? MouserStyle.accent
                                    : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct HorizontalScrollMappingsSection: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        SettingsGroup(
            "拇指滚轮",
            caption: "向左或向右拨动水平滚轮时执行动作；触控板横向滚动不会触发。"
        ) {
            horizontalRow(
                title: "向左滚动",
                detail: "水平滚轮向左",
                key: "hscroll_left"
            )
            MouserHairline()
            horizontalRow(
                title: "向右滚动",
                detail: "水平滚轮向右",
                key: "hscroll_right"
            )
        }
    }

    private func horizontalRow(title: String, detail: String, key: String) -> some View {
        SettingRow(title: title, detail: detail) {
            ActionPicker(title: title, selection: binding(for: key))
                .frame(width: 220)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.supplementalActionID(for: key) },
            set: { model.setSupplementalActionID($0, for: key) }
        )
    }
}

// MARK: - 鼠标示意图与热点

struct MouseButtonStage: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private let imagePadding: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let layout = MouseButtonStageLayout.layout(
                    for: model.deviceProfile.imageResource
                ) {
                    let imageFrame = layout.imageFrame(
                        in: proxy.size,
                        padding: imagePadding
                    )
                    MouseImage(resourceName: model.deviceProfile.imageResource)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)

                    ForEach(
                        layout.hotspots.filter {
                            model.availableButtons.contains($0.button)
                        }
                    ) { hotspot in
                        if let position = layout.position(
                            for: hotspot.button,
                            in: proxy.size,
                            padding: imagePadding
                        ) {
                            MouseHotspotButton(
                                button: hotspot.button,
                                isSelected: hotspot.button == model.selectedButton,
                                localizedTitle: model.localized(hotspot.button.title),
                                selectionNamespace: selectionNamespace
                            ) {
                                withAnimation(reduceMotion ? nil : MouserMotion.selection) {
                                    model.selectedButton = hotspot.button
                                }
                            }
                            .position(position)
                        }
                    }
                } else {
                    MouseImage(resourceName: model.deviceProfile.imageResource)
                        .padding(imagePadding)
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
                }
            }
        }
        .accessibilityLabel(
            model.formatted(
                "%@ 可交互按键示意图",
                model.localizedRuntime(model.deviceName)
            )
        )
    }
}

struct MouseHotspotButton: View {
    let button: MouseButton
    let isSelected: Bool
    let localizedTitle: String
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(MouserStyle.accent.gradient)
                        .matchedGeometryEffect(
                            id: "selected-mouse-button",
                            in: selectionNamespace
                        )
                }

                Circle()
                    .fill(.clear)
                    .glassEffect(
                        .regular
                            .tint(
                                isSelected
                                    ? MouserStyle.accent.opacity(0.30)
                                    : Color.white.opacity(0.68)
                            )
                            .interactive(),
                        in: .circle
                    )
                    .overlay {
                        Circle().stroke(
                            isSelected ? Color.white.opacity(0.9) : MouserStyle.accent,
                            lineWidth: isSelected ? 2 : 2.5
                        )
                    }
            }
            .frame(
                width: isSelected ? 25 : 20,
                height: isSelected ? 25 : 20
            )
            .scaleEffect(
                isHovered && !reduceMotion
                    ? 1.14
                    : isSelected ? 1.06 : 1
            )
            .shadow(
                color: MouserStyle.accent.opacity(
                    isHovered ? 0.45 : isSelected ? 0.38 : 0.20
                ),
                radius: isHovered ? 11 : isSelected ? 9 : 6
            )
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .animation(
                reduceMotion ? nil : MouserMotion.hover,
                value: isHovered
            )
        }
        .buttonStyle(.plain)
        .help(localizedTitle)
        .accessibilityLabel(localizedTitle)
    }
}

private struct GestureMappingEditor: View {
    @Bindable var model: WorkspaceModel
    let button: MouseButton

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("手势动作")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(GestureMappingSlot.allCases) { slot in
                ActionPicker(title: model.localized(slot.title), selection: binding(for: slot))
            }
        }
        .padding(11)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: MouserStyle.radiusInner, style: .continuous)
        )
    }

    private func binding(for slot: GestureMappingSlot) -> Binding<String> {
        Binding(
            get: { model.gestureActionID(for: button, slot: slot) },
            set: { model.setGestureActionID($0, for: button, slot: slot) }
        )
    }
}

// MARK: - 动作选择与快捷键录制

struct ActionPicker: View {
    private static let captureActionID = "__capture_custom_shortcut__"

    let title: String
    @Binding var selection: String
    var includesGestureSwipe = false
    @State private var showsShortcutRecorder = false

    private var pickerSelection: Binding<String> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == Self.captureActionID {
                    showsShortcutRecorder = true
                } else {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        Picker(title, selection: pickerSelection) {
            if includesGestureSwipe {
                Section("手势") {
                    Text("按住并滑动").tag("gesture_swipe")
                }
            }
            if let shortcut = CustomShortcut(actionID: selection) {
                Section("当前快捷键") {
                    Text(shortcut.displayText).tag(shortcut.actionID)
                }
            }
            ForEach(MouserActionCategory.allCases, id: \.self) { category in
                Section {
                    ForEach(MouserAction.allCases.filter { $0.category == category }) { action in
                        Text(LocalizedStringKey(action.title)).tag(action.rawValue)
                    }
                } header: {
                    Text(LocalizedStringKey(category.title))
                }
            }
            Section("自定义") {
                Text("录制快捷键…").tag(Self.captureActionID)
            }
        }
        .pickerStyle(.menu)
        .sheet(isPresented: $showsShortcutRecorder) {
            ShortcutCaptureSheet { shortcut in
                selection = shortcut.actionID
            }
        }
    }
}

private struct ShortcutCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var recorderFocused: Bool
    @State private var shortcut: CustomShortcut?
    let onSave: (CustomShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("录制快捷键")
                    .font(.system(size: 17, weight: .semibold))
                Text("点按下方区域，然后按下一个组合键。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 7) {
                Image(systemName: shortcut == nil ? "keyboard" : "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        shortcut == nil
                            ? AnyShapeStyle(MouserStyle.accent)
                            : AnyShapeStyle(MouserStyle.connected)
                    )
                Text(shortcut?.displayText ?? "等待输入…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("支持 ⌃ Control、⇧ Shift、⌥ Option 和 ⌘ Command")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(
                MouserStyle.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: MouserStyle.radiusInner, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MouserStyle.radiusInner, style: .continuous)
                    .stroke(
                        recorderFocused ? MouserStyle.accent : Color.secondary.opacity(0.2),
                        lineWidth: 2
                    )
            }
            .contentShape(Rectangle())
            .focusable()
            .focused($recorderFocused)
            .onKeyPress(phases: [.down]) { keyPress in
                capture(keyPress)
            }
            .onTapGesture { recorderFocused = true }

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("使用快捷键") {
                    guard let shortcut else { return }
                    onSave(shortcut)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(shortcut == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { recorderFocused = true }
    }

    private func capture(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let key = keyName(for: keyPress) else { return .ignored }
        var modifiers: [String] = []
        if keyPress.modifiers.contains(.control) { modifiers.append("ctrl") }
        if keyPress.modifiers.contains(.shift) { modifiers.append("shift") }
        if keyPress.modifiers.contains(.option) { modifiers.append("alt") }
        if keyPress.modifiers.contains(.command) { modifiers.append("super") }
        guard let captured = CustomShortcut(modifiers: modifiers, key: key) else {
            return .ignored
        }
        shortcut = captured
        return .handled
    }

    private func keyName(for keyPress: KeyPress) -> String? {
        switch keyPress.key {
        case .return: "enter"
        case .tab: "tab"
        case .space: "space"
        case .delete: "backspace"
        case .deleteForward: "delete"
        case .escape: "escape"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .upArrow: "up"
        case .downArrow: "down"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pageup"
        case .pageDown: "pagedown"
        default:
            printableKeyName(keyPress.characters)
        }
    }

    private func printableKeyName(_ characters: String) -> String? {
        let lowered = characters.lowercased()
        if lowered.count == 1,
           let scalar = lowered.unicodeScalars.first {
            if ("a"..."z").contains(lowered) || ("0"..."9").contains(lowered) {
                return lowered
            }
            if (0xF704...0xF717).contains(scalar.value) {
                return "f\(scalar.value - 0xF703)"
            }
            return [
                "=": "equal", "-": "minus", "[": "leftbracket",
                "]": "rightbracket", ";": "semicolon", "'": "quote",
                "\\": "backslash", ",": "comma", ".": "period",
                "/": "slash", "`": "grave",
            ][lowered]
        }
        return nil
    }
}
