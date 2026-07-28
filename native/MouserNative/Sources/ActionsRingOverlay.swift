import AppKit
import Observation
import SwiftUI

@MainActor
protocol ActionsRingOverlayPresenting: AnyObject {
    func show(
        slots: [String],
        highlightedIndex: Int?,
        interactive: Bool,
        language: AppLanguage,
        at screenPoint: NSPoint,
        onSelect: @escaping @MainActor (Int) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    )
    func updateHighlight(_ index: Int?)
    func hide()
}

struct ActionsRingSlotPresentation: Identifiable, Equatable, Sendable {
    let id: Int
    let actionID: String
    let title: String
    let systemImage: String

    init(index: Int, actionID: String) {
        id = index
        self.actionID = actionID
        if let shortcut = CustomShortcut(actionID: actionID) {
            title = shortcut.displayText
            systemImage = "keyboard"
        } else if let action = MouserAction(rawValue: actionID) {
            title = action.title
            systemImage = action.ringSystemImage
        } else {
            title = actionID
            systemImage = "bolt"
        }
    }
}

private extension MouserAction {
    var ringSystemImage: String {
        switch self {
        case .missionControl, .legacyTaskView: "rectangle.3.group"
        case .appExpose: "macwindow.on.rectangle"
        case .showDesktop, .legacyShowDesktop: "rectangle.inset.filled"
        case .launchpad: "square.grid.3x3.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.end.fill"
        case .previousTrack: "backward.end.fill"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .volumeMute: "speaker.slash.fill"
        case .copy: "doc.on.doc"
        case .paste: "clipboard"
        case .cut: "scissors"
        case .browserBack, .previousDesktop: "chevron.left"
        case .browserForward, .nextDesktop: "chevron.right"
        case .screenshotRegionClipboard, .screenshotRegionFile,
             .screenshotFullClipboard, .screenshotFullFile: "camera.viewfinder"
        case .switchScrollMode, .toggleSmartShift: "scroll"
        case .cycleDPI: "scope"
        case .mouseLeft, .mouseRight, .mouseMiddle, .mouseBack, .mouseForward: "computermouse"
        case .activateActionsRing: "circle.hexagongrid"
        case .passThrough: "minus"
        default: "bolt.fill"
        }
    }
}

@Observable
@MainActor
private final class ActionsRingPresentation {
    var slots: [ActionsRingSlotPresentation] = []
    var highlightedIndex: Int?
    var interactive = false
    var locale = Locale(identifier: "en")
    var onSelect: (@MainActor (Int) -> Void)?
    var onDismiss: (@MainActor () -> Void)?
}

@MainActor
final class ActionsRingOverlayController: ActionsRingOverlayPresenting {
    private static let panelSize = NSSize(width: 340, height: 340)

    private let presentation = ActionsRingPresentation()
    private var panel: NSPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func show(
        slots: [String],
        highlightedIndex: Int?,
        interactive: Bool,
        language: AppLanguage,
        at screenPoint: NSPoint,
        onSelect: @escaping @MainActor (Int) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        let panel = panel ?? makePanel()
        presentation.slots = slots.enumerated().map {
            ActionsRingSlotPresentation(index: $0.offset, actionID: $0.element)
        }
        presentation.highlightedIndex = highlightedIndex
        presentation.interactive = interactive
        presentation.locale = language.locale
        presentation.onSelect = onSelect
        presentation.onDismiss = onDismiss
        panel.ignoresMouseEvents = !interactive
        panel.setFrameOrigin(Self.origin(around: screenPoint, size: panel.frame.size))
        panel.orderFrontRegardless()
        if interactive { installOutsideClickMonitors(for: panel) }
        else { removeOutsideClickMonitors() }
    }

    func updateHighlight(_ index: Int?) {
        presentation.highlightedIndex = index
    }

    func hide() {
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
        presentation.highlightedIndex = nil
        presentation.onSelect = nil
        presentation.onDismiss = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: ActionsRingOverlayView(presentation: presentation))
        self.panel = panel
        return panel
    }

    private static func origin(around point: NSPoint, size: NSSize) -> NSPoint {
        let desired = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        guard let frame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        else { return desired }
        return NSPoint(
            x: min(max(desired.x, frame.minX), frame.maxX - size.width),
            y: min(max(desired.y, frame.minY), frame.maxY - size.height)
        )
    }

    private func installOutsideClickMonitors(for panel: NSPanel) {
        removeOutsideClickMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self, weak panel] event in
            guard let self, event.window !== panel else { return event }
            self.presentation.onDismiss?()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.presentation.onDismiss?() }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}

private struct ActionsRingOverlayView: View {
    @Bindable var presentation: ActionsRingPresentation

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 310, height: 310)
                .glassEffect(.regular, in: .circle)

            ForEach(presentation.slots) { slot in
                slotButton(slot)
                    .offset(offset(for: slot.id, count: presentation.slots.count))
            }

            Button {
                presentation.onDismiss?()
            } label: {
                Image(systemName: presentation.interactive ? "xmark" : "circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.thinMaterial, in: .circle)
            .disabled(!presentation.interactive)
            .accessibilityLabel("关闭操作环")
        }
        .frame(width: 340, height: 340)
        .contentShape(Circle())
        .environment(\.locale, presentation.locale)
    }

    private func slotButton(_ slot: ActionsRingSlotPresentation) -> some View {
        let highlighted = presentation.highlightedIndex == slot.id
        return Button {
            presentation.onSelect?(slot.id)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: slot.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(LocalizedStringKey(slot.title))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 88, height: 66)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(highlighted ? MouserStyle.accent : Color.clear, in: .rect(cornerRadius: 18))
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .scaleEffect(highlighted ? 1.07 : 1)
            .animation(.smooth(duration: 0.16), value: highlighted)
        }
        .buttonStyle(.plain)
        .disabled(!presentation.interactive)
        .accessibilityLabel(Text(LocalizedStringKey(slot.title)))
    }

    private func offset(for index: Int, count: Int) -> CGSize {
        guard count > 0 else { return .zero }
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
        let radius = count > 6 ? 116.0 : 108.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}
