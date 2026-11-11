import CoreGraphics
import Testing

@testable import EmulsionUI

struct WorkspaceRegionTests {
    @Test(arguments: [
        RegionCase(name: "No obstruction", obstacles: [], area: 800000),
        RegionCase(name: "Book division", obstacles: [.init(x: 490, y: 0, width: 20, height: 800)], area: 392000),
        RegionCase(name: "Tabletop division", obstacles: [.init(x: 0, y: 390, width: 1000, height: 20)], area: 390000),
        RegionCase(name: "Camera frame includes margins", obstacles: [.init(x: 950, y: 300, width: 50, height: 100)], area: 760000),
        RegionCase(name: "Outside canvas", obstacles: [.init(x: 1200, y: 0, width: 30, height: 100)], area: 800000),
        RegionCase(name: "Clipped camera", obstacles: [.init(x: 970, y: -40, width: 80, height: 100)], area: 776000),
        RegionCase(name: "Inactive division", obstacles: [.init(x: 500, y: 0, width: 0, height: 800)], area: 800000),
        RegionCase(
            name: "Camera and division",
            obstacles: [.init(x: 490, y: 0, width: 20, height: 800), .init(x: 950, y: 300, width: 50, height: 100)], area: 392000),
        RegionCase(name: "Physical left edge", obstacles: [.init(x: 0, y: 300, width: 50, height: 100)], area: 760000),
    ])
    func canvasStaysWithinTheUsableRegion(_ fixture: RegionCase) {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = WorkspaceRegion.largestRectangle(in: bounds, avoiding: fixture.obstacles)
        #expect(bounds.contains(frame))
        #expect(frame.width * frame.height == fixture.area)
        for obstacle in fixture.obstacles where !obstacle.isEmpty {
            #expect(frame.intersection(obstacle).isEmpty)
        }
    }
}

struct RegionCase: Sendable {
    let name: String
    let obstacles: [CGRect]
    let area: CGFloat
}
