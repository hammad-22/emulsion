import EmulsionFixtures
import XCTest

@testable import EmulsionCore

final class PipelineTests: EmulsionTestCase {
    func testMaterializedNegativeRendersIdenticallyIncludingHeadroom() throws {
        let (wedge, _) = SceneFixtures.wedge()
        let lazy = Negative(image: wedge, source: .raw)
        let cached = try renderer.materialize(lazy)
        let a = codes(try renderer.render(lazy, .neutral))
        let b = codes(try renderer.render(cached, .neutral))
        // Half-float storage: values above 1 (scene highlights) must survive.
        for (x, y) in zip(a, b) { for c in 0..<3 { XCTAssertEqual(x[c], y[c], accuracy: 0.6) } }
    }
}
