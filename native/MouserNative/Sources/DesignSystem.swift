import AppKit
import SwiftUI

/// Mouser 视觉体系 —— macOS 27 Liquid Glass 原生实现：
/// 动态环境光画布 + `glassEffect` 玻璃卡片 + 系统玻璃控件，界面随状态呼吸。
enum MouserStyle {
    /// 唯一强调色：Apple 蓝。仅用于交互元素与选中态。
    static let accent = adaptive(
        light: RGB(red: 0, green: 113, blue: 227),
        dark: RGB(red: 10, green: 132, blue: 255)
    )
    /// 环境光副色：Mouser 品牌青，只作背景光晕，不进入控件。
    static let ambientTeal = adaptive(
        light: RGB(red: 10, green: 159, blue: 146),
        dark: RGB(red: 50, green: 214, blue: 194)
    )
    static let connected = adaptive(
        light: RGB(red: 43, green: 159, blue: 94),
        dark: RGB(red: 52, green: 199, blue: 89)
    )
    static let warning = adaptive(
        light: RGB(red: 224, green: 98, blue: 13),
        dark: RGB(red: 255, green: 159, blue: 10)
    )

    /// 画布底色：玻璃之下需要有内容才能折射，环境光球负责层次。
    static let canvasBackground = adaptive(
        light: RGB(red: 233, green: 234, blue: 238),
        dark: RGB(red: 22, green: 23, blue: 27)
    )
    static let cardBackground = adaptive(
        light: RGB(red: 255, green: 255, blue: 255),
        dark: RGB(red:41, green: 43, blue: 49)
    )

    static let radiusPanel: CGFloat = 20
    static let radiusCard: CGFloat = 18
    static let radiusInner: CGFloat = 12
    static let radiusControl: CGFloat = 10
    static let radiusRow: CGFloat = 8

    private struct RGB {
        let red: Int
        let green: Int
        let blue: Int

        var nsColor: NSColor {
            NSColor(
                red: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
    }

    private static func adaptive(light: RGB, dark: RGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.nsColor
                : light.nsColor
        })
    }
}

enum MouserMotion {
    static let hover = Animation.easeOut(duration: 0.14)
    static let selection = Animation.spring(duration: 0.35, bounce: 0.12)
    static let reveal = Animation.smooth(duration: 0.3)
    static let numeric = Animation.spring(duration: 0.45, bounce: 0.2)
    static let orbDrift = Animation.linear(duration: 14).repeatForever(autoreverses: true)
}

struct WindowAppearanceBridge: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> WindowAppearanceView {
        let view = WindowAppearanceView()
        view.apply(mode)
        return view
    }

    func updateNSView(_ nsView: WindowAppearanceView, context: Context) {
        nsView.apply(mode)
    }
}

@MainActor
final class WindowAppearanceView: NSView {
    private var mode: AppearanceMode = .system

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    func apply(_ mode: AppearanceMode) {
        self.mode = mode
        applyAppearance()
    }

    private func applyAppearance() {
        configureWindowChrome()
        switch mode {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func configureWindowChrome() {
        guard let window else { return }
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

// MARK: - 动态环境光画布

/// 液态玻璃需要背后有色彩才会折射；两团缓慢漂移的环境光让界面「呼吸」。
struct MouserBackground: View {
    var glow: Color = MouserStyle.ambientTeal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MouserStyle.canvasBackground

                AmbientOrb(
                    color: glow,
                    size: max(proxy.size.width * 0.5, 380),
                    drift: drifting
                )
                .offset(
                    x: proxy.size.width * 0.66,
                    y: -proxy.size.height * 0.30
                )

                AmbientOrb(
                    color: MouserStyle.accent,
                    size: max(proxy.size.width * 0.38, 300),
                    drift: drifting
                )
                .offset(
                    x: -proxy.size.width * 0.42,
                    y: proxy.size.height * 0.44
                )
                .opacity(0.8)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion, !drifting else { return }
            withAnimation(MouserMotion.orbDrift) { drifting = true }
        }
    }
}

struct AmbientOrb: View {
    let color: Color
    let size: CGFloat
    var drift: Bool = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.22), color.opacity(0.02)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: size * 0.18)
            .offset(
                x: drift ? size * 0.06 : -size * 0.04,
                y: drift ? size * 0.05 : -size * 0.05
            )
            .allowsHitTesting(false)
    }
}

// MARK: - 玻璃表面

/// macOS 27 系统液态玻璃卡片；玻璃自带折射与高光边，不再叠实色底。
private struct MouserGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .glassEffect(
                tint.map { .regular.tint($0.opacity(0.16)) } ?? .regular,
                in: shape
            )
            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }
}

extension View {
    func mouserCard(
        cornerRadius: CGFloat = MouserStyle.radiusCard,
        tint: Color? = nil
    ) -> some View {
        modifier(MouserGlassCard(cornerRadius: cornerRadius, tint: tint))
    }

    /// 悬停时轻微浮起，用于可点卡片，赋予玻璃生命感。
    func mouserHoverLift() -> some View {
        modifier(MouserHoverLiftModifier())
    }

    func mouserReveal(delay: Double = 0) -> some View {
        modifier(MouserRevealModifier(delay: delay))
    }
}

private struct MouserHoverLiftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1)
            .shadow(
                color: .black.opacity(isHovered ? 0.16 : 0.10),
                radius: isHovered ? 18 : 14,
                y: isHovered ? 9 : 6
            )
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : MouserMotion.hover, value: isHovered)
    }
}

/// 卡片内嵌列表的分隔发丝线；与 SettingRow 的左内边距对齐。
struct MouserHairline: View {
    var leadingInset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

struct MouserRevealModifier: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let revealed = reduceMotion || isVisible

        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(MouserMotion.reveal.delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

// MARK: - 通用小组件

/// 品牌徽章：蓝色渐变 + 顶部高光 + 蓝色投影。
struct MouserIconBadge: View {
    let systemImage: String
    var size: CGFloat = 34

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.48, blue: 0.95),
                            Color(red: 0.04, green: 0.35, blue: 0.78),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LinearGradient(
                colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.47, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size, height: size)
        .shadow(
            color: Color(red: 18.0 / 255, green: 92.0 / 255, blue: 205.0 / 255).opacity(0.35),
            radius: 2.5,
            y: 2
        )
        .accessibilityHidden(true)
    }
}

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? MouserStyle.connected : Color.secondary)
            .frame(width: 7, height: 7)
            .shadow(
                color: active ? MouserStyle.connected.opacity(0.55) : .clear,
                radius: 3.5
            )
            .accessibilityHidden(true)
    }
}

/// 状态胶囊：圆点 + 文字，语义色 12% 淡染底。
struct StatusPill: View {
    let title: String
    let tint: Color
    var active: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? tint : Color.secondary)
                .frame(width: 6, height: 6)
            Text(LocalizedStringKey(title))
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(active ? tint : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            (active ? tint : Color.secondary).opacity(0.12),
            in: Capsule()
        )
    }
}

/// 页面标题。
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserReveal()
    }
}

// MARK: - 设置行与分组

struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 14)
            control
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12.5, weight: .semibold))
                if let caption {
                    Text(LocalizedStringKey(caption))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mouserCard(cornerRadius: MouserStyle.radiusInner + 2)
        }
    }
}
