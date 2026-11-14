import Accelerate
import Foundation

/// SSIM on CIE L* with the constants of Wang et al., IEEE TIP 13(4), 2004 (docs/CONSTANTS.md).
enum StructuralSimilarity {
    static let windowSigma: Float = 1.5
    static let windowRadius = 5
    static let windowSize = 2 * windowRadius + 1
    static let dynamicRange: Float = 100
    static let c1 = (0.01 * dynamicRange) * (0.01 * dynamicRange)
    static let c2 = (0.03 * dynamicRange) * (0.03 * dynamicRange)

    /// Over pixels whose whole window lies inside the image, as the paper and scikit-image do.
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

    static let kernel: [Float] = {
        let taps = (-windowRadius...windowRadius).map { exp(-Float($0 * $0) / (2 * windowSigma * windowSigma)) }
        let sum = taps.reduce(0, +)
        return taps.map { $0 / sum }
    }()

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
