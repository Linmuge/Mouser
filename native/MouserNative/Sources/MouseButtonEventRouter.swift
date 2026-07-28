import Foundation

struct MouseButtonSample: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case down
        case up
    }

    static let injectedEventMarker: Int64 = 0x4D4F5554

    let kind: Kind
    let buttonNumber: Int64
    let sourceUserData: Int64

    init(kind: Kind, buttonNumber: Int64, sourceUserData: Int64 = 0) {
        self.kind = kind
        self.buttonNumber = buttonNumber
        self.sourceUserData = sourceUserData
    }
}

enum MouseButtonRouteDecision: Equatable, Sendable {
    case passThrough
    case execute(String)
    case beginGesture(MouseButton)
    case endGesture(MouseButton)
    case block
}

struct MouseButtonEventRouter: Sendable {
    private var mappings: [MouseButton: String]
    private var swallowedButtons: Set<MouseButton> = []
    private var activeGestureButton: MouseButton?

    init(mappings: [MouseButton: String] = [:]) {
        self.mappings = mappings
    }

    mutating func updateMappings(_ mappings: [MouseButton: String]) {
        self.mappings = mappings
        swallowedButtons.removeAll()
        activeGestureButton = nil
    }

    mutating func route(_ sample: MouseButtonSample) -> MouseButtonRouteDecision {
        guard sample.sourceUserData != MouseButtonSample.injectedEventMarker,
              let button = Self.button(for: sample.buttonNumber)
        else { return .passThrough }

        switch sample.kind {
        case .down:
            guard let actionID = mappings[button],
                  actionID != MouserAction.passThrough.rawValue
            else { return .passThrough }
            swallowedButtons.insert(button)
            if actionID == "gesture_swipe" {
                activeGestureButton = button
                return .beginGesture(button)
            }
            return .execute(actionID)
        case .up:
            guard swallowedButtons.remove(button) != nil else { return .passThrough }
            if activeGestureButton == button {
                activeGestureButton = nil
                return .endGesture(button)
            }
            return .block
        }
    }

    static func button(for number: Int64) -> MouseButton? {
        switch number {
        case 2: .middle
        case 3: .back
        case 4: .forward
        default: nil
        }
    }
}
