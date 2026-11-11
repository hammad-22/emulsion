import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import EmulsionCore

/// Frozen scene-linear images for the visual regression suite: half-float RGBA TIFF (LZW, lossless)
/// in the working space (extended linear sRGB), read back without colour matching. Not OpenEXR:
/// ImageIO's EXR writer converts through ColorSync in float and moves half floats by a few ulps
/// (0 became −4e-5 next to 11.5), so it cannot freeze a scene exactly.
enum SceneFile {
    /// Half-float RGBA samples (IEEE 754 binary16 bit patterns), top row first.
    struct HalfImage: Equatable {
        let width: Int
        let height: Int
        let bits: [UInt16]
    }

    static func halfImage(rendering image: CIImage) -> HalfImage {
        let (w, h) = (Int(image.extent.width), Int(image.extent.height))
        var bits = [UInt16](repeating: 0, count: w * h * 4)
        RegressionImage.context.render(
            image, toBitmap: &bits, rowBytes: w * 8, bounds: image.extent, format: .RGBAh, colorSpace: Renderer.workingSpace)
        return HalfImage(width: w, height: h, bits: bits)
    }

    static func tiffData(_ image: HalfImage) throws -> Data {
        let bytes = image.bits.map(\.littleEndian).withUnsafeBytes { Data($0) }
        let bitsPerComponent = 16
        let componentsPerPixel = 4
        let info = CGImageAlphaInfo.last.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        guard let provider = CGDataProvider(data: bytes as CFData),
            let cgImage = CGImage(
                width: image.width, height: image.height, bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerComponent * componentsPerPixel, bytesPerRow: image.width * componentsPerPixel * 2,
                space: Renderer.workingSpace, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        else { throw ImageFileError(description: "cannot build a half-float image") }
        return try ImageFile.write(cgImage, as: .tiff, properties: lzw)
    }

    static func halfImage(tiffData data: Data) throws -> HalfImage {
        let image = try ImageFile.read(data)
        guard image.bitmapInfo.contains(.floatComponents), image.bitsPerPixel == 64 else {
            throw ImageFileError(description: "expected half-float RGBA TIFF, got \(image.bitsPerPixel) bits per pixel")
        }
        let samples = try ImageFile.samples(of: image)
        var bits = [UInt16]()
        bits.reserveCapacity(image.width * image.height * 4)
        for i in 0..<image.width * image.height {
            let rgb = samples.rgb(ofPixel: i)
            bits.append(rgb.x)
            bits.append(rgb.y)
            bits.append(rgb.z)
            bits.append(samples.alpha(ofPixel: i))
        }
        return HalfImage(width: image.width, height: image.height, bits: bits)
    }

    /// The scene as a working-space image, values used as stored (no colour matching).
    static func image(_ half: HalfImage) -> CIImage {
        let data = half.bits.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data, bytesPerRow: half.width * 8, size: CGSize(width: half.width, height: half.height), format: .RGBAh,
            colorSpace: Renderer.workingSpace)
    }

    static func image(contentsOf url: URL) throws -> CIImage { image(try halfImage(tiffData: Data(contentsOf: url))) }

    private static let lzwCompression = 5
    private static var lzw: CFDictionary {
        [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: lzwCompression]] as CFDictionary
    }
}
