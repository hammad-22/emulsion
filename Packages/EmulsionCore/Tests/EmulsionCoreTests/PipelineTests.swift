import EmulsionFixtures
import ImageIO
import XCTest

@testable import EmulsionCore

final class PipelineTests: EmulsionTestCase {
    func testMaterializedNegativeRendersIdenticallyIncludingHeadroom() throws {
        let (wedge, _) = SceneFixtures.wedge()
        let lazy = Negative(image: wedge, contract: .sceneReferred)
        let cached = try renderer.materialize(lazy)
        let a = codes(try renderer.render(lazy, .neutral))
        let b = codes(try renderer.render(cached, .neutral))
        // Half-float storage: values above 1 (scene highlights) must survive.
        for (x, y) in zip(a, b) { for c in 0..<3 { XCTAssertEqual(x[c], y[c], accuracy: 0.6) } }
    }

    // MARK: Export

    func testExportsAreDisplayP3AndHEICIs10Bit() throws {
        var a = Adjustments()
        a.seed = 1
        let image = try render(SceneFixtures.patches(), a)
        for format in Renderer.ExportFormat.allCases {
            let data = try renderer.export(image, format: format)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            XCTAssertEqual(props[kCGImagePropertyProfileName as String] as? String, "Display P3", "\(format)")
            XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
            if format == .heic { XCTAssertEqual(props[kCGImagePropertyDepth as String] as? Int, 10) }
        }
    }
}
