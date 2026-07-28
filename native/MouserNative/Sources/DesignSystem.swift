import SwiftUI

enum MouserStyle {
    static let accent = Color(red: 0.04, green: 0.58, blue: 0.52)
    static let connected = Color(red: 0.16, green: 0.68, blue: 0.40)
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.13)
    static let panelRadius: CGFloat = 18
    static let compactRadius: CGFloat = 12
}

extension View {
    func mouserGlass(cornerRadius: CGFloat = MouserStyle.panelRadius) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func settingsPanel() -> some View {
        self
            .background(.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: MouserStyle.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MouserStyle.panelRadius, style: .continuous)
                    .stroke(.separator.opacity(0.36), lineWidth: 0.5)
            }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.7)
            Text(LocalizedStringKey(subtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
