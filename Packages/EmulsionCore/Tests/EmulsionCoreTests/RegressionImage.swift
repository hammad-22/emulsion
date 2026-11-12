import CoreImage
import Foundation
import UniformTypeIdentifiers
import simd

@testable import EmulsionCore

/// A rendered image as 16-bit Display P3 encoded code values, top row first: the form goldens are
/// stored and compared in (16-bit RGB PNG, tagged Display P3).
struct RegressionImage: Equatable {
    static let maxCode = Double(UInt16.max)
    /// Read back like the Renderer's own context: extended linear sRGB working space, half float.
    static let context = CIContext(options: [
        .workingColorSpace: Renderer.workingSpace, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false,
    ])

    let width: Int
    let height: Int
    let pixels: [SIMD3<UInt16>]

    init(width: Int, height: Int, pixels: [SIMD3<UInt16>]) {
        precondition(pixels.count == width * height)
        (self.width, self.height, self.pixels) = (width, height, pixels)
    }

    /// Renders a working-space image to 16-bit unsigned Display P3 (Core Image quantises and clips).
    init(rendering image: CIImage) {
        let (w, h) = (Int(image.extent.width), Int(image.extent.height))
        var codes = [UInt16](repeating: 0, count: w * h * 4)
        Self.context.render(
            image, toBitmap: &codes, rowBytes: w * 8, bounds: image.extent, format: .RGBA16, colorSpace: Renderer.outputSpace)
        self.init(width: w, height: h, pixels: (0..<w * h).map { SIMD3(codes[$0 * 4], codes[$0 * 4 + 1], codes[$0 * 4 + 2]) })
    }

    /// Encoded Display P3 values in 0…1.
    var encoded: [SIMD3<Double>] { pixels.map { SIMD3<Double>($0) / Self.maxCode } }

    /// Per-pixel CIEDE2000 against another image of the same size.
    func deltaE(to other: RegressionImage) -> [Double] {
        precondition(width == other.width && height == other.height)
        return zip(encoded, other.encoded).map(ColorDifference.deltaE2000(displayP3:_:))
    }

    /// Nearest-neighbour enlargement, so one-pixel patch rows can be looked at.
    func enlarged(cell: Int) -> RegressionImage {
        let w = width * cell
        let h = height * cell
        return RegressionImage(width: w, height: h, pixels: (0..<w * h).map { pixels[($0 / w / cell) * width + ($0 % w) / cell] })
    }

    // MARK: PNG

    /// 16-bit RGB PNG, big-endian samples, tagged Display P3.
    func pngData() throws -> Data {
        var samples = [UInt16]()
        samples.reserveCapacity(pixels.count * 3)
        for pixel in pixels {
            samples.append(pixel.x.bigEndian)
            samples.append(pixel.y.bigEndian)
            samples.append(pixel.z.bigEndian)
        }
        let bytes = samples.withUnsafeBytes { Data($0) }
        let bitsPerComponent = 16
        let componentsPerPixel = 3
        guard let provider = CGDataProvider(data: bytes as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerComponent * componentsPerPixel,
                bytesPerRow: width * componentsPerPixel * 2, space: Renderer.outputSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ImageFileError(description: "cannot build a 16-bit RGB image") }
        return try ImageFile.write(image, as: .png)
    }

    /// Reads the PNG's raw samples: no colour matching, no premultiplication.
    init(pngData data: Data) throws {
        let image = try ImageFile.read(data)
        guard image.bitsPerComponent == 16, !image.bitmapInfo.contains(.floatComponents) else {
            throw ImageFileError(description: "expected 16-bit integer samples, got \(image.bitsPerComponent)-bit")
        }
        let samples = try ImageFile.samples(of: image)
        self.init(width: image.width, height: image.height, pixels: (0..<image.width * image.height).map(samples.rgb(ofPixel:)))
    }
}
