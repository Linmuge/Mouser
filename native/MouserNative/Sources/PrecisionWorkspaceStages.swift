import AppKit
import SwiftUI

private struct PrecisionStageObjectMetrics {
    let compact: Bool
    let mouseHeight: CGFloat
    let mouseX: CGFloat
    let mouseTop: CGFloat
    let haloDiameter: CGFloat
    let ringDiameter: CGFloat

    init(compact: Bool, object: Object = .regular) {
        self.compact = compact
        haloDiameter = compact ? 480 : 545
        ringDiameter = compact ? 490 : 560
        switch object {
        case .regular:
            mouseHeight = compact ? 520 : 596
            mouseX = 0.61
            mouseTop = 0.51
        case .compact:
            mouseHeight = compact ? 420 : 474
            mouseX = 0.69
            mouseTop = 0.54
        case .small:
            mouseHeight = 360
            mouseX = 0.73
            mouseTop = 0.56
        }
    }

    enum Object { case regular, compact, small }

    func mouseImageFrame(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let width = mouseHeight * aspectRatio
        let center = CGPoint(
            x: size.width * mouseX,
            y: size.height * mouseTop + mouseHeight * 0.05
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - mouseHeight / 2,
            width: width,
            height: mouseHeight
        )
    }
}

struct PrecisionOverviewStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact, object: .compact)
            ZStack(alignment: .topLeading) {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionOverviewQuickLines(model: model)
                    .offset(x: proxy.size.width * 0.43, y: proxy.size.height * 0.21)
                PrecisionStageLabels(
                    top: model.deviceName.uppercased(),
                    left: transportLabel(model),
                    right: "\(model.batteryText) BATTERY"
                )
                PrecisionMetricStrip(model: model)
            }
        }
    }
}

struct PrecisionButtonsStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact)
            let layout = MouseButtonStageLayout.layout(for: model.deviceProfile.imageResource)
            let imageFrame = layout.map {
                metrics.mouseImageFrame(
                    in: proxy.size,
                    aspectRatio: $0.imageSize.width / $0.imageSize.height
                )
            }
            ZStack {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionStageLabels(
                    top: model.deviceName.uppercased(),
                    left: transportLabel(model),
                    right: "\(model.batteryText) BATTERY"
                )
                if let layout, let imageFrame {
                    ForEach(layout.hotspots) { hotspot in
                        if model.availableButtons.contains(hotspot.button),
                           let position = layout.position(
                               for: hotspot.button,
                               in: imageFrame,
                               rotationDegrees: 1
                           ) {
                            PrecisionButtonHotspot(selected: model.selectedButton == hotspot.button) {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                    model.selectedButton = hotspot.button
                                }
                            }
                            .position(position)
                            .help(model.localized(hotspot.button.title))
                        }
                    }
                }
            }
        }
        .accessibilityLabel(model.formatted("%@ 可交互按键示意图", model.deviceName))
    }
}

struct PrecisionPointerStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact)
            ZStack(alignment: .topLeading) {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionStageLabels(
                    top: "POINTER · \(Int(model.dpi)) DPI",
                    left: "RATCHET ⟷ FREE SPIN",
                    right: "SCROLL DIRECTION"
                )
                PrecisionPointerQuickLines(model: model)
                    .offset(x: proxy.size.width * 0.43, y: proxy.size.height * 0.21)
            }
        }
    }
}

struct PrecisionHapticsStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact, object: .compact)
            ZStack {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionHapticPulseRings(active: model.hapticsEnabled)
                    .position(x: proxy.size.width * 0.61, y: proxy.size.height * 0.53)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionStageLabels(
                    top: model.hapticsEnabled ? "HAPTIC ENGINE · ACTIVE" : "HAPTIC ENGINE · OFF",
                    left: "INTENSITY \(Int((model.hapticStrength / 3) * 100))%",
                    right: ""
                )
            }
        }
    }
}

struct PrecisionActionsRingStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact, object: .compact)
            ZStack {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionEightDirectionRing(model: model, diameter: metrics.ringDiameter)
                    .position(x: proxy.size.width * 0.61, y: proxy.size.height * 0.54)
            }
        }
    }
}

struct PrecisionProfilesStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact, object: .small)
            ZStack {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionProfileStageList(model: model, compact: compact)
                    .frame(width: compact ? 390 : 365)
                    .position(
                        x: proxy.size.width * (compact ? 0.30 : 0.33) + (compact ? 195 : 182.5),
                        y: proxy.size.height * 0.25 + 164
                    )
            }
        }
    }
}

struct PrecisionAdvancedStage: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = PrecisionStageObjectMetrics(compact: compact, object: .small)
            ZStack {
                PrecisionStageBackdrop(metrics: metrics)
                PrecisionMouseObject(model: model, metrics: metrics, size: proxy.size)
                PrecisionDiagnosticStagePath(model: model)
                    .frame(width: compact ? 390 : 470)
                    .position(
                        x: proxy.size.width * (compact ? 0.30 : 0.34) + (compact ? 195 : 235),
                        y: proxy.size.height * 0.24 + 114
                    )
            }
        }
    }
}

private struct PrecisionStageBackdrop: View {
    let metrics: PrecisionStageObjectMetrics

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(MouserStyle.accent.opacity(0.10))
                    .frame(width: 410, height: 240)
                    .blur(radius: 64)
                    .position(x: proxy.size.width * 0.59, y: proxy.size.height * 0.88)
                Circle()
                    .stroke(Color.primary.opacity(0.11), lineWidth: 1)
                    .frame(width: metrics.haloDiameter, height: metrics.haloDiameter)
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.075), lineWidth: 1).padding(52)
                        Circle().stroke(Color.primary.opacity(0.065), lineWidth: 1).padding(112)
                    }
                    .position(x: proxy.size.width * 0.61, y: proxy.size.height * 0.54)
                PrecisionStageAxis(axis: .horizontal)
                    .frame(width: 650, height: 1)
                    .position(x: proxy.size.width * 0.34 + 325, y: proxy.size.height * 0.62)
                PrecisionStageAxis(axis: .vertical)
                    .frame(width: 1, height: 510)
                    .position(x: proxy.size.width * 0.61, y: proxy.size.height * 0.14 + 255)
            }
        }
    }
}

struct PrecisionStageAxis: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis

    var body: some View {
        Rectangle().fill(Color.primary.opacity(axis == .horizontal ? 0.12 : 0.10))
    }
}

private struct PrecisionMouseObject: View {
    @Bindable var model: WorkspaceModel
    let metrics: PrecisionStageObjectMetrics
    let size: CGSize

    var body: some View {
        MouseImage(resourceName: model.deviceProfile.imageResource)
            .frame(height: metrics.mouseHeight)
            .rotationEffect(.degrees(1))
            .shadow(color: .black.opacity(0.27), radius: 28, y: 38)
            .position(
                x: size.width * metrics.mouseX,
                y: size.height * metrics.mouseTop + metrics.mouseHeight * 0.05
            )
    }
}

private struct PrecisionStageLabels: View {
    let top: String
    let left: String
    let right: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PrecisionMonoLabel(top)
                    .offset(x: proxy.size.width * 0.50, y: proxy.size.height * 0.15)
                PrecisionMonoLabel(left)
                    .offset(x: proxy.size.width * 0.34, y: proxy.size.height * 0.63)
                if !right.isEmpty {
                    PrecisionMonoLabel(right)
                        .frame(width: proxy.size.width - 26, alignment: .trailing)
                        .offset(y: proxy.size.height * 0.63)
                }
            }
        }
    }
}

private struct PrecisionMonoLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(MouserStyle.muted)
            .fixedSize()
    }
}

private struct PrecisionButtonHotspot: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 30, height: 30)
                .overlay { Circle().stroke(MouserStyle.accent, lineWidth: 1) }
                .overlay { Circle().fill(MouserStyle.accent).frame(width: 10, height: 10) }
                .shadow(color: MouserStyle.accent.opacity(0.18), radius: 0, x: 0, y: 0)
                .overlay { Circle().stroke(MouserStyle.accent.opacity(0.13), lineWidth: selected ? 11 : 6) }
                .shadow(color: .black.opacity(0.18), radius: selected ? 13 : 10, y: 7)
                .scaleEffect(selected ? 1.17 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct PrecisionOverviewQuickLines: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("\(Int(model.dpi)) DPI", "指针")
            line("SmartShift", model.smartShiftEnabled ? "开启" : "关闭")
            line("唤醒恢复", "就绪")
        }
    }

    private func line(_ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.13)).frame(width: 62, height: 1)
            Text(value).fontWeight(.semibold).foregroundStyle(MouserStyle.ink)
            Text(LocalizedStringKey(label)).foregroundStyle(MouserStyle.muted)
        }
        .font(.system(size: 12))
        .fixedSize()
    }
}

private struct PrecisionPointerQuickLines: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("\(Int(model.dpiRange.lowerBound))", "最低 DPI")
            line("\(Int(model.dpi))", "当前")
            line("\(Int(model.dpiRange.upperBound))", "最高 DPI")
        }
    }
    private func line(_ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.13)).frame(width: 62, height: 1)
            Text(value).fontWeight(.semibold).foregroundStyle(MouserStyle.ink)
            Text(LocalizedStringKey(label)).foregroundStyle(MouserStyle.muted)
        }.font(.system(size: 12)).fixedSize()
    }
}

struct PrecisionMetricStrip: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 28) {
                metric(model.deviceTransport == "—" ? "Logi Bolt" : model.deviceTransport, "连接方式")
                metric("\(Int(model.dpi)) DPI", "当前速度")
                metric(model.localizedRuntime(model.selectedProfile?.name ?? "默认配置"), "应用配置")
            }
            .frame(width: max(0, proxy.size.width * 0.66 - 28), height: 48, alignment: .bottomLeading)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
            .position(x: proxy.size.width * 0.34 + max(0, proxy.size.width * 0.66 - 28) / 2, y: proxy.size.height - 44)
        }
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(MouserStyle.ink)
            Text(LocalizedStringKey(label)).font(.system(size: 11, design: .monospaced)).foregroundStyle(MouserStyle.muted)
        }.fixedSize()
    }
}

struct PrecisionHapticPulseRings: View {
    let active: Bool
    var body: some View {
        ZStack {
            ForEach([290.0, 390.0, 500.0], id: \.self) { diameter in
                Circle()
                    .stroke(MouserStyle.accent.opacity(active ? 0.28 : 0.08), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }
        }
    }
}

struct PrecisionEightDirectionRing: View {
    @Bindable var model: WorkspaceModel
    let diameter: CGFloat
    private let referencePositions: [CGPoint] = [
        CGPoint(x: 280, y: 19),
        CGPoint(x: 494, y: 127),
        CGPoint(x: 518, y: 279),
        CGPoint(x: 484, y: 448),
        CGPoint(x: 280, y: 541),
        CGPoint(x: 69, y: 448),
        CGPoint(x: 42, y: 279),
        CGPoint(x: 66, y: 127),
    ]
    private let fallback = [
        MouserAction.missionControl.rawValue, MouserAction.browserForward.rawValue,
        MouserAction.copy.rawValue, MouserAction.paste.rawValue,
        MouserAction.showDesktop.rawValue, MouserAction.browserBack.rawValue,
        MouserAction.screenshotRegionFile.rawValue, MouserAction.playPause.rawValue,
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        stops: ringGradientStops,
                        center: .center,
                        startAngle: .degrees(-22.5),
                        endAngle: .degrees(337.5)
                    )
                )
                .overlay { Circle().stroke(Color.primary.opacity(0.11), lineWidth: 1) }
                .padding(32)
            ForEach(0..<8, id: \.self) { index in
                Button {
                    model.selectedActionsRingIndex = index
                } label: {
                    Text(actionTitle(at: index))
                        .font(.system(size: 12, weight: model.selectedActionsRingIndex == index ? .bold : .regular))
                        .frame(width: 104, height: 38)
                        .foregroundStyle(model.selectedActionsRingIndex == index ? .white : .primary)
                        .background(model.selectedActionsRingIndex == index ? MouserStyle.accent : Color.clear)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .overlay { Capsule().stroke(model.selectedActionsRingIndex == index ? Color.clear : Color.primary.opacity(0.11), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.11), radius: 10, y: 8)
                }
                .buttonStyle(.plain)
                .position(
                    x: referencePositions[index].x * diameter / 560,
                    y: referencePositions[index].y * diameter / 560
                )
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func actionTitle(at index: Int) -> String {
        let slots = model.actionsRingSlots
        let actionID = slots.indices.contains(index) ? slots[index] : fallback[index]
        switch actionID {
        case MouserAction.missionControl.rawValue:
            return "Mission Control"
        case MouserAction.screenshotRegionFile.rawValue:
            return "截图"
        case MouserAction.playPause.rawValue:
            return "媒体播放"
        default:
            break
        }
        return model.localized(MouserAction(rawValue: actionID)?.title ?? "无动作")
    }

    private var ringGradientStops: [Gradient.Stop] {
        let accent = MouserStyle.accent.opacity(0.13)
        let clear = MouserStyle.accent.opacity(0)
        func location(_ degrees: Double) -> CGFloat { degrees / 360 }
        return [
            .init(color: accent, location: location(0)),
            .init(color: accent, location: location(44)),
            .init(color: clear, location: location(44)),
            .init(color: clear, location: location(90)),
            .init(color: accent, location: location(90)),
            .init(color: accent, location: location(134)),
            .init(color: clear, location: location(134)),
            .init(color: clear, location: location(180)),
            .init(color: accent, location: location(180)),
            .init(color: accent, location: location(224)),
            .init(color: clear, location: location(224)),
            .init(color: clear, location: location(270)),
            .init(color: accent, location: location(270)),
            .init(color: accent, location: location(314)),
            .init(color: clear, location: location(314)),
            .init(color: clear, location: location(360)),
        ]
    }
}

struct PrecisionProfileStageList: View {
    @Bindable var model: WorkspaceModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayProfiles.enumerated()), id: \.element.id) { index, profile in
                Button { model.selectProfile(id: profile.id) } label: {
                    HStack(spacing: 12) {
                        profileIcon(profile)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.localizedRuntime(profile.name)).font(.system(size: 14, weight: .semibold))
                            Text(model.localized(profileDetail(profile, index: index))).font(.system(size: 12)).foregroundStyle(MouserStyle.muted)
                        }
                        Spacer()
                        Text(profile.id == model.selectedProfileID ? "当前" : "编辑")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(MouserStyle.accent)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 82)
                    .contentShape(Rectangle())
                    .background(profile.id == model.selectedProfileID ? MouserStyle.accent.opacity(0.10) : Color.clear)
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1) }
                }.buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1) }
    }

    private var displayProfiles: [AppProfile] { Array(model.profiles.prefix(4)) }
    private func profileDetail(_ profile: AppProfile, index: Int) -> String {
        if profile.id == "default" { return "所有未指定应用" }
        if index == 1 { return "浏览与网页应用" }
        if index == 2 { return "开发工作区" }
        if index == 3 { return "媒体播放" }
        return profile.bundleID ?? "应用配置"
    }
    @ViewBuilder private func profileIcon(_ profile: AppProfile) -> some View {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.bundleID ?? "") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path)).resizable().frame(width: 40, height: 40)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.04, green: 0.07, blue: 0.12))
                Text(profile.id == "default" ? "M" : String(profile.name.prefix(1))).fontWeight(.heavy).foregroundStyle(.white)
            }.frame(width: 40, height: 40)
        }
    }
}

struct PrecisionDiagnosticStagePath: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            step(1, "辅助功能", "按键与滚动权限", model.accessibilityGranted ? "ALLOWED" : "REQUIRED")
            step(2, "HID++ 通道", "\(model.deviceName) · \(model.deviceTransport)", model.mouseConnected ? "CONNECTED" : "WAITING")
            step(3, "唤醒恢复", "DPI、滚轮和方向", model.configurationLoaded ? "READY" : "LOADING")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1) }
    }
    private func step(_ number: Int, _ title: String, _ detail: String, _ status: String) -> some View {
        HStack(spacing: 13) {
            Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(MouserStyle.accent)
                .frame(width: 24, height: 24).background(MouserStyle.accent.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(model.localized(title)).font(.system(size: 14, weight: .semibold))
                Text(model.localizedRuntime(detail)).font(.system(size: 12)).foregroundStyle(MouserStyle.muted)
            }
            Spacer()
            Text(status).font(.system(size: 11, design: .monospaced)).foregroundStyle(MouserStyle.connected)
        }
        .frame(minHeight: 76)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1) }
    }
}

@MainActor
private func transportLabel(_ model: WorkspaceModel) -> String {
    let transport = model.deviceTransport == "—" ? "LOGI BOLT" : model.deviceTransport.uppercased()
    return "\(transport) · \(model.mouseConnected ? "CONNECTED" : "WAITING")"
}
