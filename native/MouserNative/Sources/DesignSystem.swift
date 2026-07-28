import AppKit
import SwiftUI

enum MouserStyle {
    static let accent = adaptive(
        light: RGB(red: 10, green: 159, blue: 146),
        dark: RGB(red: 50, green: 214, blue: 194)
    )
    static let accentBlue = Color(red: 0.20, green: 0.46, blue: 0.96)
    static let accentMint = Color(red: 0.30, green: 0.82, blue: 0.68)
    static let connected = adaptive(
        light: RGB(red: 49, green: 184, blue: 117),
        dark: RGB(red: 72, green: 217, blue: 144)
    )
    static let ink = adaptive(
        light: RGB(red: 21, green: 26, blue: 28),
        dark: RGB(red: 241, green: 245, blue: 244)
    )
    static let muted = adaptive(
        light: RGB(red: 112, green: 121, blue: 124),
        dark: RGB(red: 155, green: 166, blue: 164)
    )
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.13)
    static let panelRadius: CGFloat = 24
    static let compactRadius: CGFloat = 14

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
    static let hover = Animation.smooth(duration: 0.16)
    static let selection = Animation.spring(duration: 0.34, bounce: 0.18)
    static let reveal = Animation.smooth(duration: 0.36)
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

extension View {
    func mouserGlass(cornerRadius: CGFloat = MouserStyle.panelRadius) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func mouserInteractiveGlass(
        cornerRadius: CGFloat = MouserStyle.compactRadius,
        tint: Color? = nil
    ) -> some View {
        glassEffect(
            .regular.tint(tint).interactive(),
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    func settingsPanel() -> some View {
        let shape = RoundedRectangle(
            cornerRadius: MouserStyle.panelRadius,
            style: .continuous
        )
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.primary.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            }
            .shadow(color: .black.opacity(0.055), radius: 24, y: 12)
    }

    func mouserReveal(delay: Double = 0) -> some View {
        modifier(MouserRevealModifier(delay: delay))
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
            .offset(y: revealed ? 0 : 9)
            .scaleEffect(revealed ? 1 : 0.992, anchor: .top)
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

struct MouserGlassCluster<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

struct MouserBackground: View {
    let section: WorkspaceSection

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                LinearGradient(
                    colors: [
                        MouserStyle.accent.opacity(0.07),
                        Color.clear,
                        MouserStyle.accentBlue.opacity(0.035),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                AmbientOrb(
                    color: MouserStyle.accent,
                    size: max(proxy.size.width * 0.44, 320)
                )
                .offset(
                    x: proxy.size.width * 0.34,
                    y: -proxy.size.height * 0.34
                )

                AmbientOrb(
                    color: MouserStyle.accentBlue,
                    size: max(proxy.size.width * 0.30, 240)
                )
                .opacity(0.55)
                .offset(
                    x: -proxy.size.width * 0.40,
                    y: proxy.size.height * 0.38
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct AmbientOrb: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.24), color.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .blur(radius: size * 0.24)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(MouserStyle.accent.gradient)
                .frame(width: 5, height: 46)
                .shadow(color: MouserStyle.accent.opacity(0.35), radius: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.45)
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mouserReveal()
    }
}

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? MouserStyle.connected : .secondary)
            .frame(width: 8, height: 8)
            .shadow(color: active ? MouserStyle.connected.opacity(0.45) : .clear, radius: 4)
            .accessibilityHidden(true)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 18)
            control
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, detail == nil ? 12 : 10)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.035) : .clear)
                .padding(.horizontal, 5)
        }
        .offset(y: isHovered && !reduceMotion ? -1 : 0)
        .scaleEffect(isHovered && !reduceMotion ? 1.002 : 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : MouserMotion.hover, value: isHovered)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                if let caption {
                    Text(LocalizedStringKey(caption))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .settingsPanel()
        }
    }
}
