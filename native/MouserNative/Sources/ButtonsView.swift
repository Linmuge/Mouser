import SwiftUI

struct ButtonsView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "按键映射",
                    subtitle: "选择鼠标上的按键，再指定按下时执行的动作。"
                )

                ButtonMappingStudio(model: model)
                .mouserReveal(delay: 0.04)

                HorizontalScrollMappingsSection(model: model)
                    .mouserReveal(delay: 0.08)

                SettingsGroup("全部按键", caption: "快速检查当前配置，点击一行继续编辑。") {
                    ForEach(Array(model.availableButtons.enumerated()), id: \.element) { index, button in
                        Button {
                            withAnimation(reduceMotion ? nil : MouserMotion.selection) {
                                model.selectedButton = button
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: button == model.selectedButton ? "record.circle.fill" : "circle")
                                    .foregroundStyle(button == model.selectedButton ? MouserStyle.accent : .secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(button.title))
                                        .foregroundStyle(.primary)
                                    Text(LocalizedStringKey(button.detail))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(
                                    model.localizedRuntime(
                                        model.mapping(for: button)?.actionTitle ?? "未设置"
                                    )
                                )
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < model.availableButtons.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .mouserReveal(delay: 0.12)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ButtonMappingStudio: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MouseButtonStage(model: model)
                .frame(minWidth: 430, idealWidth: 540, maxWidth: .infinity)

            MappingInspector(model: model)
                .frame(width: 344)
                .offset(x: -18)
                .padding(.vertical, 18)
        }
        .padding(.trailing, -18)
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
            Divider().padding(.leading, 16)
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
            .frame(width: 230)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.supplementalActionID(for: key) },
            set: { model.setSupplementalActionID($0, for: key) }
        )
    }
}

private struct MouseButtonStage: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private let imagePadding: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MouseButtonStageBackdrop()
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
                        .shadow(color: .black.opacity(0.22), radius: 30, y: 18)

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
                        .shadow(color: .black.opacity(0.22), radius: 30, y: 18)
                }
            }
        }
        .frame(height: 440)
        .accessibilityLabel(
            model.formatted(
                "%@ 可交互按键示意图",
                model.localizedRuntime(model.deviceName)
            )
        )
    }
}

private struct MouseButtonStageBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    colors: [
                        MouserStyle.accent.opacity(0.18),
                        Color.clear,
                        MouserStyle.accentBlue.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.48),
                                Color.primary.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 32, y: 18)
    }
}

private struct MouseHotspotButton: View {
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
                                    ? MouserStyle.accent.opacity(0.28)
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
                    isHovered ? 0.48 : isSelected ? 0.4 : 0.22
                ),
                radius: isHovered ? 12 : isSelected ? 10 : 6
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

private struct MappingInspector: View {
    @Bindable var model: WorkspaceModel

    private var selectedActionID: Binding<String> {
        Binding(
            get: {
                model.mapping(for: model.selectedButton)?.actionID
                    ?? MouserAction.passThrough.rawValue
            },
            set: { model.setActionID($0, for: model.selectedButton) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("正在编辑")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MouserStyle.accent)
                Text(LocalizedStringKey(model.selectedButton.title))
                    .font(.title2.bold())
                Text(LocalizedStringKey(model.selectedButton.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("按下时执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ActionPicker(
                    title: "动作",
                    selection: selectedActionID,
                    includesGestureSwipe: model.selectedButton.supportsSlideGesture
                )
                .controlSize(.large)
            }

            if selectedActionID.wrappedValue == "gesture_swipe" {
                GestureMappingEditor(model: model, button: model.selectedButton)
            } else if selectedActionID.wrappedValue == MouserAction.paste.rawValue {
                LabeledContent("发送快捷键") {
                    Text("⌘V")
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
            }

            Spacer()

            Label("更改会自动保存", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(MouserStyle.connected)
        }
        .padding(24)
        .frame(
            minHeight: 404,
            maxHeight: selectedActionID.wrappedValue == "gesture_swipe" ? 570 : 404,
            alignment: .topLeading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.44), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.11), radius: 26, y: 14)
    }
}

private struct GestureMappingEditor: View {
    @Bindable var model: WorkspaceModel
    let button: MouseButton

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手势动作")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(GestureMappingSlot.allCases) { slot in
                ActionPicker(title: model.localized(slot.title), selection: binding(for: slot))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func binding(for slot: GestureMappingSlot) -> Binding<String> {
        Binding(
            get: { model.gestureActionID(for: button, slot: slot) },
            set: { model.setGestureActionID($0, for: button, slot: slot) }
        )
    }
}

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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("录制快捷键")
                    .font(.title2.bold())
                Text("点按下方区域，然后按下一个组合键。")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Image(systemName: shortcut == nil ? "keyboard" : "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(shortcut == nil ? MouserStyle.accent : MouserStyle.connected)
                Text(shortcut?.displayText ?? "等待输入…")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("支持 ⌃ Control、⇧ Shift、⌥ Option 和 ⌘ Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .background(MouserStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
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
                .disabled(shortcut == nil)
            }
        }
        .padding(24)
        .frame(width: 430)
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
