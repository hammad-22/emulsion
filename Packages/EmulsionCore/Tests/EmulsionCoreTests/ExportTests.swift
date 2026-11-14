import CoreImage
import EmulsionFixtures
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import EmulsionCore

/// Exports read back through ImageIO, independently of the engine (docs/CONSTANTS.md).
@Suite struct ExportTests {
    /// The red is outside sRGB, so a file tagged or converted as sRGB comes back clipped.
    static let patches: [SIMD3<Float>] = [
        SIMD3(0.90, 0.10, 0.10), SIMD3(0.20, 0.80, 0.30), SIMD3(0.15, 0.20, 0.85), SIMD3(0.50, 0.50, 0.50),
    ]
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
        /// Measured worst, 8-bit steps, quality 0.95: JPEG 0.88, HEIC 0.18.
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
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32
        #expect(orientation == nil || orientation == CGImagePropertyOrientation.up.rawValue)

        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.colorSpace?.name == CGColorSpace.displayP3)
        #expect(decoded.bitsPerComponent == expected.bitDepth)

        let values = Fixtures.encodedFloats(CIImage(cgImage: decoded), space: Renderer.outputSpace)
        for (index, patch) in Self.patches.enumerated() {
            let centre = (Self.height / 2) * Self.width + index * Self.block + Self.block / 2
            let error = values[centre] - SIMD3<Double>(patch)
            let worst = max(abs(error.x), abs(error.y), abs(error.z)) * 255
            #expect(worst <= expected.tolerance, "patch \(index): \(values[centre]) vs \(patch)")
        }
    }

    @Test(arguments: formats) func exportsOfACameraPhotoAreUprightWithoutLocation(_ expected: Expected) throws {
        let renderer = EmulsionTestCase.sharedRenderer
        let developed = try renderer.developer.develop(Self.cameraJPEG())
        let data = try renderer.export(renderer.render(developed, .neutral), format: expected.format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        #expect(properties[kCGImagePropertyProfileName] as? String == "Display P3")
        #expect(properties[kCGImagePropertyDepth] as? Int == expected.bitDepth)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32
        #expect(orientation == nil || orientation == CGImagePropertyOrientation.up.rawValue)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Self.height, "rotated to portrait once")
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == Self.width)
    }

    /// Stored landscape, tagged "rotate 90° clockwise to view", with a GPS position.
    static func cameraJPEG() throws -> Data {
        let context = CIContext()
        let scene = try #require(context.createCGImage(Self.image, from: Self.image.extent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let location = [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"] as CFDictionary
        let metadata =
            [
                kCGImagePropertyGPSDictionary: location,
                kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue,
            ] as CFDictionary
        CGImageDestinationAddImage(destination, scene, metadata)
        #expect(CGImageDestinationFinalize(destination))
        let written = try #require(CGImageSourceCreateWithData(data, nil))
        let writtenProperties = CGImageSourceCopyPropertiesAtIndex(written, 0, nil) as? [CFString: Any]
        #expect(writtenProperties?[kCGImagePropertyGPSDictionary] != nil, "the fixture must carry a location")
        return data as Data
    }
}
