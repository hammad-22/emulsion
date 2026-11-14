import XCTest

extension XCUIScreenshot {
    /// Every pixel black, judged on an 8×8 reduction.
    var isBlank: Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let image = image.cgImage,
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels.enumerated().allSatisfy { index, value in index % 4 == 3 || value == 0 }
    }
}
