import Foundation

struct HIDPPButtonEvent: Equatable, Sendable {
    let button: MouseButton
    let isPressed: Bool
}

enum HIDPPSpecialInputEvent: Equatable, Sendable {
    case button(HIDPPButtonEvent)
    case movement(dx: Int16, dy: Int16)
}

struct HIDPPSpecialInputRouter: Sendable {
    private let featureIndex: UInt8
    private var buttonRouter: HIDPPButtonEventRouter

    init(featureIndex: UInt8, buttonsByCID: [UInt16: MouseButton]) {
        self.featureIndex = featureIndex
        buttonRouter = HIDPPButtonEventRouter(
            featureIndex: featureIndex,
            buttonsByCID: buttonsByCID
        )
    }

    mutating func route(_ response: HIDPPResponse) -> [HIDPPSpecialInputEvent] {
        guard response.featureIndex == featureIndex else { return [] }
        if response.function == 1, response.parameters.count >= 4 {
            let rawX = UInt16(response.parameters[0]) << 8 | UInt16(response.parameters[1])
            let rawY = UInt16(response.parameters[2]) << 8 | UInt16(response.parameters[3])
            return [.movement(
                dx: Int16(bitPattern: rawX),
                dy: Int16(bitPattern: rawY)
            )]
        }
        return buttonRouter.route(response).map(HIDPPSpecialInputEvent.button)
    }
}

struct HIDPPButtonEventRouter: Sendable {
    let featureIndex: UInt8
    let buttonsByCID: [UInt16: MouseButton]
    private var pressedCIDs: Set<UInt16> = []

    init(featureIndex: UInt8, buttonsByCID: [UInt16: MouseButton]) {
        self.featureIndex = featureIndex
        self.buttonsByCID = buttonsByCID
    }

    mutating func route(_ response: HIDPPResponse) -> [HIDPPButtonEvent] {
        guard response.featureIndex == featureIndex, response.function == 0 else { return [] }
        let reportedCIDs = Self.cids(in: response.parameters)
        var events: [HIDPPButtonEvent] = []
        for cid in buttonsByCID.keys.sorted() {
            guard let button = buttonsByCID[cid] else { continue }
            let wasPressed = pressedCIDs.contains(cid)
            let isPressed = reportedCIDs.contains(cid)
            if wasPressed != isPressed {
                events.append(HIDPPButtonEvent(button: button, isPressed: isPressed))
            }
        }
        pressedCIDs = reportedCIDs.intersection(buttonsByCID.keys)
        return events
    }

    private static func cids(in parameters: [UInt8]) -> Set<UInt16> {
        var result: Set<UInt16> = []
        var offset = 0
        while offset + 1 < parameters.count {
            let cid = UInt16(parameters[offset]) << 8 | UInt16(parameters[offset + 1])
            if cid == 0 { break }
            result.insert(cid)
            offset += 2
        }
        return result
    }
}
