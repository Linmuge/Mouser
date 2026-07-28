import CoreGraphics

struct MouseButtonHotspot: Identifiable, Equatable, Sendable {
    let button: MouseButton
    let normalizedPosition: CGPoint

    var id: MouseButton { button }
}

struct MouseButtonStageLayout: Equatable, Sendable {
    let imageSize: CGSize
    let hotspots: [MouseButtonHotspot]

    static func layout(for resourceName: String?) -> Self? {
        switch resourceName {
        case nil, "mx-master-3s":
            Self(
                imageSize: CGSize(width: 636, height: 1024),
                hotspots: [
                    MouseButtonHotspot(button: .middle, normalizedPosition: CGPoint(x: 0.68, y: 0.20)),
                    MouseButtonHotspot(button: .modeShift, normalizedPosition: CGPoint(x: 0.78, y: 0.375)),
                    MouseButtonHotspot(button: .forward, normalizedPosition: CGPoint(x: 0.382, y: 0.447)),
                    MouseButtonHotspot(button: .back, normalizedPosition: CGPoint(x: 0.417, y: 0.55)),
                    MouseButtonHotspot(button: .gesture, normalizedPosition: CGPoint(x: 0.075, y: 0.60)),
                    MouseButtonHotspot(button: .actionsRing, normalizedPosition: CGPoint(x: 0.16, y: 0.66)),
                ]
            )
        case "mouse_mx_anywhere_3s":
            Self(
                imageSize: CGSize(width: 1280, height: 720),
                hotspots: [
                    MouseButtonHotspot(button: .middle, normalizedPosition: CGPoint(x: 0.345, y: 0.49)),
                    MouseButtonHotspot(button: .modeShift, normalizedPosition: CGPoint(x: 0.44, y: 0.30)),
                    MouseButtonHotspot(button: .forward, normalizedPosition: CGPoint(x: 0.745, y: 0.49)),
                    MouseButtonHotspot(button: .back, normalizedPosition: CGPoint(x: 0.69, y: 0.57)),
                ]
            )
        case "mx_vertical":
            Self(
                imageSize: CGSize(width: 1118, height: 960),
                hotspots: [
                    MouseButtonHotspot(button: .middle, normalizedPosition: CGPoint(x: 0.22, y: 0.41)),
                    MouseButtonHotspot(button: .forward, normalizedPosition: CGPoint(x: 0.61, y: 0.28)),
                    MouseButtonHotspot(button: .back, normalizedPosition: CGPoint(x: 0.55, y: 0.31)),
                    MouseButtonHotspot(button: .dpiSwitch, normalizedPosition: CGPoint(x: 0.605, y: 0.11)),
                ]
            )
        default:
            nil
        }
    }

    func normalizedPosition(for button: MouseButton) -> CGPoint? {
        hotspots.first(where: { $0.button == button })?.normalizedPosition
    }

    func imageFrame(in containerSize: CGSize, padding: CGFloat) -> CGRect {
        let availableSize = CGSize(
            width: max(0, containerSize.width - padding * 2),
            height: max(0, containerSize.height - padding * 2)
        )
        guard imageSize.width > 0,
              imageSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0
        else {
            return CGRect(origin: CGPoint(x: containerSize.width / 2, y: containerSize.height / 2), size: .zero)
        }
        let scale = min(
            availableSize.width / imageSize.width,
            availableSize.height / imageSize.height
        )
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func position(
        for button: MouseButton,
        in containerSize: CGSize,
        padding: CGFloat
    ) -> CGPoint? {
        guard let normalizedPosition = normalizedPosition(for: button) else { return nil }
        let frame = imageFrame(in: containerSize, padding: padding)
        return CGPoint(
            x: frame.minX + frame.width * normalizedPosition.x,
            y: frame.minY + frame.height * normalizedPosition.y
        )
    }

    func position(
        for button: MouseButton,
        in imageFrame: CGRect,
        rotationDegrees: CGFloat
    ) -> CGPoint? {
        guard let normalizedPosition = normalizedPosition(for: button) else { return nil }
        let point = CGPoint(
            x: imageFrame.minX + imageFrame.width * normalizedPosition.x,
            y: imageFrame.minY + imageFrame.height * normalizedPosition.y
        )
        guard rotationDegrees != 0 else { return point }

        let radians = rotationDegrees * .pi / 180
        let deltaX = point.x - imageFrame.midX
        let deltaY = point.y - imageFrame.midY
        return CGPoint(
            x: imageFrame.midX + deltaX * cos(radians) - deltaY * sin(radians),
            y: imageFrame.midY + deltaX * sin(radians) + deltaY * cos(radians)
        )
    }
}
