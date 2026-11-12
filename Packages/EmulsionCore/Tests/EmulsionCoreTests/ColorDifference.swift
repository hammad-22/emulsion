import Foundation
import simd

@testable import EmulsionCore

/// CIEDE2000 colour difference on Display P3 encoded output, for the visual regression suite.
/// Checked against colour-science and Sharma, Wu & Dalal (2005) in `References/delta-e.json`.
enum ColorDifference {
    private static let displayP3 = InputColorSpace.displayP3
    /// The display's D65 white as XYZ (Y = 1).
    private static let white = ColorMath.xyz(displayP3.primaries.white)
    /// Linear Display P3 → XYZ (normalised primary matrix).
    private static let p3ToXYZ: simd_double3x3 = {
        let p = displayP3.primaries
        return ColorMath.rgbToXYZ(p.r, p.g, p.b, white: p.white)
    }()

    /// Display P3 encoded (sRGB transfer) → CIELAB. The Lab white is the display's own D65 and no
    /// chromatic adaptation is applied: both images compared share that white.
    static func lab(fromDisplayP3 encoded: SIMD3<Double>) -> SIMD3<Double> {
        let linear = SIMD3(decode(encoded.x), decode(encoded.y), decode(encoded.z))
        let xyz = p3ToXYZ * linear / white
        let f = SIMD3(labCompand(xyz.x), labCompand(xyz.y), labCompand(xyz.z))
        return SIMD3(116 * f.y - 16, 500 * (f.x - f.y), 200 * (f.y - f.z))
    }

    /// CIEDE2000 between two Display P3 encoded colours.
    static func deltaE2000(displayP3 a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        deltaE2000(lab(fromDisplayP3: a), lab(fromDisplayP3: b))
    }

    private static func decode(_ v: Double) -> Double { ColorMath.decode(v, curve: displayP3.curve) }

    /// CIE 1976 lightness companding: ε = 216/24389, κ = 24389/27.
    private static func labCompand(_ t: Double) -> Double {
        t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
    }

    /// CIEDE2000 with kL = kC = kH = 1, following Sharma, Wu & Dalal (2005).
    static func deltaE2000(_ lab1: SIMD3<Double>, _ lab2: SIMD3<Double>) -> Double {
        let chromaMean = (hypot(lab1.y, lab1.z) + hypot(lab2.y, lab2.z)) / 2
        let chromaMean7 = pow(chromaMean, 7)
        let g = 0.5 * (1 - (chromaMean7 / (chromaMean7 + pow(25, 7))).squareRoot())
        let a1 = (1 + g) * lab1.y
        let a2 = (1 + g) * lab2.y
        let c1 = hypot(a1, lab1.z)
        let c2 = hypot(a2, lab2.z)
        let h1 = hueDegrees(a1, lab1.z)
        let h2 = hueDegrees(a2, lab2.z)

        let deltaL = lab2.x - lab1.x
        let deltaC = c2 - c1
        let chromaProduct = c1 * c2
        var deltaHue = 0.0
        if chromaProduct != 0 {
            deltaHue = h2 - h1
            if deltaHue > 180 { deltaHue -= 360 } else if deltaHue < -180 { deltaHue += 360 }
        }
        let deltaH = 2 * chromaProduct.squareRoot() * sin(radians(deltaHue / 2))

        let lMean = (lab1.x + lab2.x) / 2
        let cMean = (c1 + c2) / 2
        var hMean = h1 + h2
        if chromaProduct != 0 {
            hMean = abs(h1 - h2) <= 180 ? hMean / 2 : (hMean < 360 ? (hMean + 360) / 2 : (hMean - 360) / 2)
        }
        let t =
            1 - 0.17 * cos(radians(hMean - 30)) + 0.24 * cos(radians(2 * hMean)) + 0.32 * cos(radians(3 * hMean + 6))
            - 0.20 * cos(radians(4 * hMean - 63))
        let lOffset = (lMean - 50) * (lMean - 50)
        let sL = 1 + 0.015 * lOffset / (20 + lOffset).squareRoot()
        let sC = 1 + 0.045 * cMean
        let sH = 1 + 0.015 * cMean * t
        let cMean7 = pow(cMean, 7)
        let rC = 2 * (cMean7 / (cMean7 + pow(25, 7))).squareRoot()
        let deltaTheta = 30 * exp(-pow((hMean - 275) / 25, 2))
        let rT = -sin(radians(2 * deltaTheta)) * rC

        let l = deltaL / sL
        let c = deltaC / sC
        let h = deltaH / sH
        return (l * l + c * c + h * h + rT * c * h).squareRoot()
    }

    private static func hueDegrees(_ a: Double, _ b: Double) -> Double {
        guard a != 0 || b != 0 else { return 0 }
        let h = atan2(b, a) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Summary statistics of per-pixel differences.
    struct Summary: Codable, Equatable, Sendable {
        let mean: Double
        /// Nearest-rank 95th percentile: sorted[⌈0.95·n⌉ − 1].
        let p95: Double
        /// Nearest-rank 99.9th percentile: what is left after ignoring the worst pixel in a thousand.
        let p999: Double
        let max: Double
        let count: Int

        init(_ values: [Double]) {
            count = values.count
            guard !values.isEmpty else {
                (mean, p95, p999, max) = (0, 0, 0, 0)
                return
            }
            let sorted = values.sorted()
            mean = values.reduce(0, +) / Double(values.count)
            p95 = sorted[Self.nearestRank(perMille: 950, count: values.count) - 1]
            p999 = sorted[Self.nearestRank(perMille: 999, count: values.count) - 1]
            max = sorted[sorted.count - 1]
        }

        /// ⌈perMille · count / 1000⌉ in integers, so no rounding error can move the rank.
        private static func nearestRank(perMille: Int, count: Int) -> Int { (perMille * count + 999) / 1000 }
    }
}
