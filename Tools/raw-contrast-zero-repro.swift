// Minimal reproduction of Apple's CIRAWFilter tile corruption at contrastAmount 0 (MOV-147), with no Emulsion code.
//   swiftc -O Tools/raw-contrast-zero-repro.swift -o /tmp/raw-repro
//   /tmp/raw-repro <file.dng> [renders] [contrast] [localToneMapAmount] [output folder]
// Renders the full-size decode `renders` times (default 6), each from a fresh CIRAWFilter with contrastAmount set
// (default 0) and, if given, localToneMapAmount, through a CIContext that doesn't cache intermediates, and compares
// each render tile by tile with a reference render of the same decode through a caching context. Prints the corrupt
// tiles per render; with an output folder, writes reference.png and the first corrupt render as corrupt.png.
// Reproduced on macOS 27.2 (M4 Max): an iPhone 15 Pro Max 48 MP ProRAW file with contrast 0 alone, a 12 MP iPhone 12 Pro
// ProRAW file with contrast 0 and localToneMapAmount 0. Contrast 1e-4 never corrupts.
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: raw-repro <file.dng> [renders] [contrast] [localToneMapAmount] [output folder]")
    exit(2)
}
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let renders = arguments.count > 2 ? Int(arguments[2]) ?? 6 : 6
let contrast = arguments.count > 3 ? Float(arguments[3]) ?? 0 : 0
let localToneMap = arguments.count > 4 ? Float(arguments[4]) : nil
let outputFolder = arguments.count > 5 ? URL(fileURLWithPath: arguments[5], isDirectory: true) : nil
let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
let tile = 256
let corruptTileMeanCodes = 3.0

func decode() -> CIImage {
    guard let raw = CIRAWFilter(imageData: data, identifierHint: "com.adobe.raw-image") else { fatalError("not a RAW file") }
    if raw.isContrastSupported { raw.contrastAmount = contrast }
    if let localToneMap, raw.isLocalToneMapSupported { raw.localToneMapAmount = localToneMap }
    guard let output = raw.outputImage else { fatalError("no decode") }
    return output
}

func render(_ image: CIImage, cachingIntermediates: Bool) -> [UInt8] {
    let context = CIContext(options: [.cacheIntermediates: cachingIntermediates])
    let width = Int(image.extent.width)
    var pixels = [UInt8](repeating: 0, count: width * Int(image.extent.height) * 4)
    pixels.withUnsafeMutableBytes {
        context.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: displayP3)
    }
    return pixels
}

func writePNG(_ pixels: [UInt8], width: Int, height: Int, named name: String) {
    guard let outputFolder, let provider = CGDataProvider(data: Data(pixels) as CFData),
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: displayP3,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent),
        let destination = CGImageDestinationCreateWithURL(
            outputFolder.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let reference = render(decode(), cachingIntermediates: true)
let extent = decode().extent
let width = Int(extent.width)
let height = Int(extent.height)
let toneMapNote = localToneMap.map { ", localToneMapAmount \($0)" } ?? ""
print("\(width)×\(height), contrast \(contrast)\(toneMapNote), \(renders) uncached renders against a cached reference")
writePNG(reference, width: width, height: height, named: "reference.png")
var corruptRenders = 0
for index in 0..<renders {
    let pixels = render(decode(), cachingIntermediates: false)
    var corrupt: [String] = []
    for ty in stride(from: 0, to: height, by: tile) {
        for tx in stride(from: 0, to: width, by: tile) {
            var sum = 0
            var count = 0
            for y in ty..<min(ty + tile, height) {
                for x in tx..<min(tx + tile, width) {
                    for c in 0..<3 { sum += abs(Int(pixels[(y * width + x) * 4 + c]) - Int(reference[(y * width + x) * 4 + c])) }
                    count += 3
                }
            }
            let mean = Double(sum) / Double(count)
            if mean > corruptTileMeanCodes { corrupt.append("(\(tx),\(ty)) \(String(format: "%.0f", mean))") }
        }
    }
    if !corrupt.isEmpty {
        if corruptRenders == 0 { writePNG(pixels, width: width, height: height, named: "corrupt.png") }
        corruptRenders += 1
    }
    print("render \(index): \(corrupt.count) corrupt tiles\(corrupt.isEmpty ? "" : ", e.g. " + corrupt.prefix(3).joined(separator: ", "))")
}
print("\(corruptRenders) of \(renders) renders corrupt")
exit(corruptRenders == 0 ? 0 : 1)
