import Accelerate
import Foundation

/// SSIM (Wang, Bovik, Sheikh & Simoncelli, "Image quality assessment: from error visibility to
/// structural similarity", IEEE TIP 13(4), 2004) on CIE L*, with the paper's constants: an 11×11
/// Gaussian window of σ 1.5 px, K1 0.01, K2 0.03, dynamic range L 100 (L*). Written from the paper
/// with vImage convolutions; no third-party code. Single scale: the photo goldens are 240 px on the
/// long edge, too small for the five halvings of MS-SSIM.
enum StructuralSimilarity {
    static let windowSigma: Float = 1.5
    static let windowRadius = 5
    static let windowSize = 2 * windowRadius + 1
    static let dynamicRange: Float = 100
    static let c1 = (0.01 * dynamicRange) * (0.01 * dynamicRange)
    static let c2 = (0.03 * dynamicRange) * (0.03 * dynamicRange)

    /// Mean SSIM of two planes of `width` × `height`, over the pixels whose whole window lies inside
    /// the image (as the paper and scikit-image do), so the edge handling of the blur does not count.
    static func index(_ x: [Float], _ y: [Float], width: Int, height: Int) -> Double {
        precondition(min(width, height) >= windowSize && x.count == width * height && y.count == x.count)
        let muX = gaussian(x, width: width, height: height)
        let muY = gaussian(y, width: width, height: height)
        let xx = gaussian(vDSP.multiply(x, x), width: width, height: height)
        let yy = gaussian(vDSP.multiply(y, y), width: width, height: height)
        let xy = gaussian(vDSP.multiply(x, y), width: width, height: height)
        var total = 0.0
        let rows = windowRadius..<(height - windowRadius)
        let columns = windowRadius..<(width - windowRadius)
        for row in rows {
            for column in columns {
                let i = row * width + column
                let (mx, my) = (muX[i], muY[i])
                let varX = xx[i] - mx * mx
                let varY = yy[i] - my * my
                let cov = xy[i] - mx * my
                let numerator = (2 * mx * my + c1) * (2 * cov + c2)
                let denominator = (mx * mx + my * my + c1) * (varX + varY + c2)
                total += Double(numerator / denominator)
            }
        }
        return total / Double(rows.count * columns.count)
    }

    /// Normalised Gaussian window, `windowSize` taps.
    static let kernel: [Float] = {
        let taps = (-windowRadius...windowRadius).map { exp(-Float($0 * $0) / (2 * windowSigma * windowSigma)) }
        let sum = taps.reduce(0, +)
        return taps.map { $0 / sum }
    }()

    /// Separable Gaussian blur.
    static func gaussian(_ plane: [Float], width: Int, height: Int) -> [Float] {
        var input = plane
        var output = [Float](repeating: 0, count: plane.count)
        input.withUnsafeMutableBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                var source = vImage_Buffer(
                    data: src.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.stride)
                var destination = vImage_Buffer(
                    data: dst.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.stride)
                let error = kernel.withUnsafeBufferPointer { k in
                    vImageSepConvolve_PlanarF(
                        &source, &destination, nil, 0, 0, k.baseAddress, UInt32(k.count), k.baseAddress, UInt32(k.count), 0, 0,
                        vImage_Flags(kvImageEdgeExtend))
                }
                precondition(error == kvImageNoError, "vImageSepConvolve_PlanarF failed: \(error)")
            }
        }
        return output
    }
}
