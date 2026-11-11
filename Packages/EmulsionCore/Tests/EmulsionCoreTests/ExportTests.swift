import CoreImage
import EmulsionFixtures
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import EmulsionCore

/// Exported files read back through ImageIO, independently of the engine: the tags a reader
/// sees (format, ICC profile, bit depth, orientation, size) and the Display P3 values it decodes.
/// Video export doesn't exist yet, so only stills are covered (MOV-126).
@Suite struct ExportTests {
    /// Display P3 code values, one flat block each. The red is outside sRGB, so a file tagged
    /// or converted as sRGB would come back clipped.
    static let patches: [SIMD3<Float>] = [
        SIMD3(0.90, 0.10, 0.10), SIMD3(0.20, 0.80, 0.30), SIMD3(0.15, 0.20, 0.85), SIMD3(0.50, 0.50, 0.50),
    ]
    /// Blocks are large and flat so chroma subsampling and compression leave their centres
    /// alone; wider than tall so a swapped orientation shows up as swapped dimensions.
    static let block = 32
    static let width = block * patches.count
    static let height = block

    static let image = Fixtures.image(width: width, height: height, space: Renderer.outputSpace) { x, _ in
        patches[x / block]
    }

    struct Expected: CustomTestStringConvertible, Sendable {
        let format: Renderer.ExportFormat
        let type: UTType
        let bitDepth: Int
        /// Largest code-value error at a block centre, in 8-bit steps. Measured on Xcode 27.2 at
        /// quality 0.95: JPEG 0.88, HEIC 0.18 (8-bit rounding alone is up to 0.5).
        let tolerance: Double
        var testDescription: String { format.rawValue }
    }

    static let formats = [
        Expected(format: .jpeg, type: .jpeg, bitDepth: 8, tolerance: 1.5),
        Expected(format: .heic, type: .heic, bitDepth: 10, tolerance: 0.5),
    ]

    @Test(arguments: formats) func exportsAreDisplayP3AndKeepTheirValues(_ expected: Expected) throws {
        let data = try EmulsionTestCase.sharedRenderer.export(Self.image, format: expected.format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        #expect(CGImageSourceGetType(source) as String? == expected.type.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyProfileName] as? String == "Display P3")
        #expect(properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String)
        #expect(properties[kCGImagePropertyDepth] as? Int == expected.bitDepth)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Self.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == Self.height)
        // Exports are written upright: no orientation tag, or "up" (1).
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32
        #expect(orientation == nil || orientation == CGImagePropertyOrientation.up.rawValue)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil, "source metadata isn't carried over")

        // The decoder, not just the metadata, must see Display P3 at the stated depth.
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)
        #expect(decoded.bitsPerComponent == expected.bitDepth)

        // Decoding honours the embedded profile; reading back in Display P3 gives the code values.
        let values = Fixtures.encodedFloats(CIImage(cgImage: decoded), space: Renderer.outputSpace)
        for (index, patch) in Self.patches.enumerated() {
            let centre = (Self.height / 2) * Self.width + index * Self.block + Self.block / 2
            let error = values[centre] - SIMD3<Double>(patch)
            let worst = max(abs(error.x), abs(error.y), abs(error.z)) * 255
            #expect(worst <= expected.tolerance, "patch \(index): \(values[centre]) vs \(patch)")
        }
    }
}
