import CoreGraphics
import Testing
@testable import MouserNative

@Suite("Mouse button stage layout")
struct MouseButtonStageLayoutTests {
    @Test("receiver placeholder uses the default MX Master artwork layout")
    func receiverPlaceholderUsesDefaultMasterLayout() {
        #expect(
            MouseButtonStageLayout.layout(for: nil)
                == MouseButtonStageLayout.layout(for: "mx-master-3s")
        )
    }

    @Test("MX Master hotspots match the controls in the source image")
    func masterHotspotsMatchImageControls() throws {
        let layout = try #require(
            MouseButtonStageLayout.layout(for: "mx-master-3s")
        )

        #expect(layout.normalizedPosition(for: .middle) == CGPoint(x: 0.68, y: 0.20))
        #expect(layout.normalizedPosition(for: .modeShift) == CGPoint(x: 0.78, y: 0.375))
        #expect(layout.normalizedPosition(for: .forward) == CGPoint(x: 0.382, y: 0.447))
        #expect(layout.normalizedPosition(for: .back) == CGPoint(x: 0.417, y: 0.55))
        #expect(layout.normalizedPosition(for: .gesture) == CGPoint(x: 0.075, y: 0.60))
    }

    @Test("hotspots follow the centered aspect-fit image when the stage widens")
    func hotspotsFollowAspectFitImage() throws {
        let layout = try #require(
            MouseButtonStageLayout.layout(for: "mx-master-3s")
        )
        let compactPosition = try #require(
            layout.position(
                for: .middle,
                in: CGSize(width: 399, height: 390),
                padding: 32
            )
        )
        let widePosition = try #require(
            layout.position(
                for: .middle,
                in: CGSize(width: 500, height: 390),
                padding: 32
            )
        )

        #expect(abs(widePosition.x - compactPosition.x - 50.5) < 0.01)
        #expect(abs(widePosition.y - compactPosition.y) < 0.01)
    }

    @Test("hotspots project onto controls inside the displayed mouse frame")
    func hotspotsProjectOntoDisplayedMouseFrame() throws {
        let layout = try #require(
            MouseButtonStageLayout.layout(for: "mx-master-3s")
        )
        let imageFrame = CGRect(x: 338, y: 91, width: 323, height: 520)

        let middle = try #require(
            layout.position(for: .middle, in: imageFrame, rotationDegrees: 0)
        )
        let modeShift = try #require(
            layout.position(for: .modeShift, in: imageFrame, rotationDegrees: 0)
        )
        let forward = try #require(
            layout.position(for: .forward, in: imageFrame, rotationDegrees: 0)
        )
        let back = try #require(
            layout.position(for: .back, in: imageFrame, rotationDegrees: 0)
        )
        let gesture = try #require(
            layout.position(for: .gesture, in: imageFrame, rotationDegrees: 0)
        )

        #expect(abs(middle.x - 557.64) < 0.001 && abs(middle.y - 195) < 0.001)
        #expect(abs(modeShift.x - 589.94) < 0.001 && abs(modeShift.y - 286) < 0.001)
        #expect(abs(forward.x - 461.386) < 0.001 && abs(forward.y - 323.44) < 0.001)
        #expect(abs(back.x - 472.691) < 0.001 && abs(back.y - 377) < 0.001)
        #expect(abs(gesture.x - 362.225) < 0.001 && abs(gesture.y - 403) < 0.001)
    }
}

@Suite("Precision range quantizer")
struct PrecisionRangeQuantizerTests {
    @Test("values keep the requested step without exposing slider tick marks")
    func valuesKeepRequestedStep() {
        #expect(
            PrecisionRangeQuantizer.quantize(
                1_624,
                step: 50,
                range: 200...8_000
            ) == 1_600
        )
        #expect(
            PrecisionRangeQuantizer.quantize(
                1_626,
                step: 50,
                range: 200...8_000
            ) == 1_650
        )
    }

    @Test("quantized values remain inside the supported range")
    func valuesStayInsideRange() {
        #expect(
            PrecisionRangeQuantizer.quantize(
                50,
                step: 50,
                range: 200...8_000
            ) == 200
        )
        #expect(
            PrecisionRangeQuantizer.quantize(
                9_000,
                step: 50,
                range: 200...8_000
            ) == 8_000
        )
    }
}
