import CoreImage
import EmulsionFixtures
import XCTest

@testable import EmulsionCore

/// Mac timing of the full render at preview, 12 MP and 48 MP. Opt-in: EMULSION_PERF=1.
final class PerformanceProbe: XCTestCase {
    func testTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run")
        let r = try Renderer()
        var a = Adjustments()
        a.grain = 0.5
        a.halation = 0.5
        a.shadows = 0.3
        a.highlights = 0.3
        a.seed = 2
        for (w, h) in [(1600, 1200), (4032, 3024), (8064, 6048)] {
            let scene = Fixtures.image(width: 64, height: 48, space: SceneFixtures.linear) { x, y in
                SIMD3(Float(x) / 16, Float(y) / 24, 0.18)
            }
            .samplingLinear().transformed(by: CGAffineTransform(scaleX: CGFloat(w) / 64, y: CGFloat(h) / 48))
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            let neg = Negative(image: scene, contract: .sceneReferred)
            for (label, adj) in [("look only", Adjustments.neutral), ("full", a)] {
                var times = [Double]()
                for _ in 0..<5 {
                    let t = Date()
                    let cg = try r.cgImage(try r.render(neg, adj))
                    _ = cg.dataProvider?.data
                    times.append(Date().timeIntervalSince(t) * 1000)
                }
                print(String(format: "%dx%d %@: median %.1f ms (first %.1f)", w, h, label, times.dropFirst().sorted()[2], times[0]))
            }
        }
    }
}
