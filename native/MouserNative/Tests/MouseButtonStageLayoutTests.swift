import CoreGraphics
import Testing
@testable import MouserNative

@Suite("Mouse button stage layout")
struct MouseButtonStageLayoutTests {
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
}
