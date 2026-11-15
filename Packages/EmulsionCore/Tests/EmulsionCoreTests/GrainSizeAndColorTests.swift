import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Grain size (clumps that keep a narrower frame's low-frequency granularity) and grain color (the
/// color part of the layers' density noise, scaled about P3 luminance), MOV-30.
struct GrainSizeAndColorTests {

    /// Exact discrete Gaussian taps of the kernel `gaussianPass`, normalised.
    private static func taps(sigma: Double) -> [Double] {
        let radius = Int(Kernels.gaussianRadius(sigma: sigma))
        let w = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = w.reduce(0, +)
        return w.map { $0 / total }
    }

    private static func noise(size: Double, seed: Double = 5, width: Int = 2048, height: Int = 512) throws -> [SIMD3<Double>] {
        // Clumps are sized to the long edge, so the field is a strip of a full-size frame.
        let extent = CGRect(x: 0, y: 0, width: Grain.clumpReferenceLongEdge, height: Double(height))
        let field = try EmulsionTestCase.kernels.grainNoise(extent, seed: seed, size: size)
        return Fixtures.linear(field.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)))
    }

    /// Per-pixel variance is the taps' Σw² (measured within 0.2%), and 16×16 block means keep a white
    /// field's variance, 1/k², after the clump's edge loss F² (measured +3.1…3.9%): low-frequency power is kept.
    @Test(arguments: [1.5, 2, 3])
    func clumpsKeepLowFrequencyPower(size: Double) throws {
        let (width, height, block) = (2048, 512, 16)
        let sigma = Grain.clumpSigmaPixels(size: size, longEdge: Grain.clumpReferenceLongEdge)
        let w = Self.taps(sigma: sigma)
        let field = try Self.noise(size: size, width: width, height: height)
        let red = field.map(\.x)
        let pixelVariance = pow(GrainMeasurement.standardDeviation(red), 2)
        let expectedPixel = pow(w.map { $0 * $0 }.reduce(0, +), 2)
        let means = GrainMeasurement.areaReduced(
            field, width: width, scale: Double(block), outWidth: width / block, outHeight: height / block
        ).values.map(\.x)
        let radius = w.count / 2
        let coverage = (-radius..<(block + radius)).map { j in
            (0..<block).map { i in abs(i - j) <= radius ? w[i - j + radius] : 0 }.reduce(0, +)
        }
        let edgeLoss = coverage.map { $0 * $0 }.reduce(0, +) / Double(block)
        let blockRatio = pow(GrainMeasurement.standardDeviation(means), 2) * Double(block * block) / (edgeLoss * edgeLoss)
        print(
            String(
                format: "GRAIN size %.1f: clump σ %.3f px, pixel variance %.4f (Σw² %.4f), block ratio %.4f", size, sigma, pixelVariance,
                expectedPixel, blockRatio))
        #expect(abs(pixelVariance / expectedPixel - 1) < 0.03)
        #expect(abs(blockRatio - 1) < 0.08)
        #expect(GrainMeasurement.lagCorrelation(red, width: width, height: height, dx: 1, dy: 0) > 0.1)
    }

    /// The one-pass clump kernel equals the normalised Gaussian sum of the CPU noise copy over its taps
    /// (what the two-pass blur computed), negative coordinates included. Measured: worst 3.8e-7.
    @Test(arguments: [0.49, 0.85, 1.7])
    func clumpKernelIsTheGaussianSumOfTheNoise(sigma: Double) throws {
        let (seed, side) = (5.0, 48)
        let extent = CGRect(x: -16, y: -8, width: side, height: side)
        let kernels = EmulsionTestCase.kernels
        let gpu = Fixtures.linear(try kernels.run(kernels.grainClumpNoise, extent, [seed, sigma]))
        let w = Self.taps(sigma: sigma)
        let radius = w.count / 2
        var worst = 0.0
        for row in 0..<side {
            for column in 0..<side {
                var sum = SIMD3<Double>.zero
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let n = GrainMeasurement.referenceNoise(x: Int32(column - 16 + dx), y: Int32(row - 8 + dy), seed: Float(seed))
                        sum += SIMD3<Double>(n) * (w[dx + radius] * w[dy + radius])
                    }
                }
                worst = max(worst, simd_reduce_max(simd_abs(sum - gpu[row * side + column])))
            }
        }
        print(String(format: "GRAIN clump kernel vs CPU Gaussian sum, σ %.2f px: worst %.3g", sigma, worst))
        #expect(worst <= 1e-5)
    }

    /// Where a clump is narrower than `Grain.minimumClumpSigmaPixels` the noise is the white field itself.
    @Test func previewSizedClumpsAreTheWhiteNoise() throws {
        let extent = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        #expect(Grain.clumpSigmaPixels(size: 3, longEdge: 1600) < Grain.minimumClumpSigmaPixels)
        let clumped = Fixtures.linear(try EmulsionTestCase.kernels.grainNoise(extent, seed: 2, size: 3))
        let white = Fixtures.linear(try EmulsionTestCase.kernels.grainNoise(extent, seed: 2))
        #expect(clumped == white)
    }

    /// Color only changes the color part: P3 luminance of the density is the same at every color, and
    /// color 0 puts it on every layer alike.
    @Test func colorKeepsTheLuminancePart() {
        let logE = SIMD3(0.2, -0.1, 0.4)
        let n = SIMD3(1.3, -0.7, 0.4)
        let measured = Grain.density(logExposure: logE, noise: n, amount: 1, size: 1, color: 1, longEdge: 1600)
        #expect(measured == Grain.densitySigma(logExposure: logE, amount: 1, size: 1, longEdge: 1600) * n)
        for color in [0, 0.3, 0.7] {
            let g = Grain.density(logExposure: logE, noise: n, amount: 1, size: 1, color: color, longEdge: 1600)
            #expect(abs(dot(g, FilmModel.p3Luminance) - dot(measured, FilmModel.p3Luminance)) < 1e-15)
        }
        let mono = Grain.density(logExposure: logE, noise: n, amount: 1, size: 1, color: 0, longEdge: 1600)
        #expect(abs(mono.x - mono.y) < 1e-15 && abs(mono.y - mono.z) < 1e-15)
    }

    /// Through the print at mid-gray, 1600 px: color 0 correlates the display channels (r > 0.9) where
    /// the measured color does not (r < 0.3, measured 0.10, 0.17); display luma σ moves by under 10% (measured 3.4%). Size 1.5 raises luma σ
    /// by 1.5 (the clump is narrower than a pixel here), within 5% (measured 0.1%).
    @Test func displayedGrainFollowsColorAndSize() throws {
        func displayed(size: Double, color: Double) throws -> [SIMD3<Double>] {
            var a = Adjustments.neutral
            (a.grain, a.grainSize, a.grainColor, a.seed) = (1, size, color, 3)
            let image = try EmulsionTestCase.render(GrainMeasurement.flat(stops: 0, width: 1600, height: 1200), a)
            return GrainMeasurement.linearCrop(image, size: 512)
        }
        func correlations(_ linear: [SIMD3<Double>]) -> (Double, Double) {
            let c = linear.map(GrainMeasurement.codes)
            return (GrainMeasurement.correlation(c.map(\.x), c.map(\.y)), GrainMeasurement.correlation(c.map(\.y), c.map(\.z)))
        }
        let lumaSD = GrainMeasurement.lumaSD
        let measured = try displayed(size: 1, color: 1)
        let mono = try displayed(size: 1, color: 0)
        let coarse = try displayed(size: 1.5, color: 1)
        let (rgMeasured, gbMeasured) = correlations(measured)
        let (rgMono, gbMono) = correlations(mono)
        print(
            String(
                format: "GRAIN color: r(R,G) %.3f→%.3f r(G,B) %.3f→%.3f; luma σ %.3f mono %.3f size 1.5 %.3f", rgMeasured, rgMono,
                gbMeasured, gbMono, lumaSD(measured), lumaSD(mono), lumaSD(coarse)))
        #expect(rgMeasured < 0.3 && gbMeasured < 0.3)
        #expect(rgMono > 0.9 && gbMono > 0.9)
        #expect(abs(lumaSD(mono) / lumaSD(measured) - 1) < 0.1)
        #expect(abs(lumaSD(coarse) / lumaSD(measured) / 1.5 - 1) < 0.05)
    }
}
