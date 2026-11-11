import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageFileError: Error, CustomStringConvertible {
    let description: String
}

/// ImageIO reads and writes, and raw 16-bit sample access, shared by goldens and frozen scenes.
enum ImageFile {
    static func write(_ image: CGImage, as type: UTType, properties: CFDictionary? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImageFileError(description: "no \(type.identifier) encoder")
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw ImageFileError(description: "\(type.identifier) encode failed") }
        return data as Data
    }

    static func read(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ImageFileError(description: "unreadable image") }
        return image
    }

    /// Raw 16-bit samples of a CGImage with 3 or 4 components per pixel, in host byte order.
    struct Samples {
        let values: [UInt16]
        let rowSamples: Int
        let width: Int
        let componentsPerPixel: Int
        let alphaFirst: Bool

        private func pixelStart(_ index: Int) -> Int { (index / width) * rowSamples + (index % width) * componentsPerPixel }
        private func colorStart(_ index: Int) -> Int { pixelStart(index) + (alphaFirst ? 1 : 0) }

        func rgb(ofPixel index: Int) -> SIMD3<UInt16> {
            let c = colorStart(index)
            return SIMD3(values[c], values[c + 1], values[c + 2])
        }

        /// The fourth component (4-component layouts only).
        func alpha(ofPixel index: Int) -> UInt16 { values[pixelStart(index) + (alphaFirst ? 0 : 3)] }
    }

    static func samples(of image: CGImage) throws -> Samples {
        let componentsPerPixel = image.bitsPerPixel / image.bitsPerComponent
        guard image.bitsPerComponent == 16, componentsPerPixel == 3 || componentsPerPixel == 4, image.bytesPerRow % 2 == 0,
            let data = image.dataProvider?.data as Data?
        else {
            throw ImageFileError(description: "unsupported layout: \(image.bitsPerComponent) bits, \(image.bitsPerPixel) bits per pixel")
        }
        let alphaFirstLayouts: Set<CGImageAlphaInfo> = [.first, .premultipliedFirst, .noneSkipFirst]
        // 16-bit samples without an explicit order are big-endian (Quartz default).
        let bigEndian = image.bitmapInfo.intersection(.byteOrderMask) != .byteOrder16Little
        let values = data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: UInt16.self).map { bigEndian ? UInt16(bigEndian: $0) : UInt16(littleEndian: $0) }
        }
        return Samples(
            values: values, rowSamples: image.bytesPerRow / 2, width: image.width, componentsPerPixel: componentsPerPixel,
            alphaFirst: componentsPerPixel == 4 && alphaFirstLayouts.contains(image.alphaInfo))
    }
}
