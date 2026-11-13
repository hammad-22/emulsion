import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Grain v2 (MOV-30): per-layer negative density noise, σ from the datasheet's granularity table,
/// scaled to the pixel by Selwyn's law, white at the pixel scale, printed through the film.
struct GrainTests {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    private static let fieldSide = 1024

    private static func adjustments(grain: Double, seed: Double = 3) -> Adjustments {
        var a = Adjustments.neutral
        (a.grain, a.seed) = (grain, seed)
        return a
    }

    private func noise(seed: Double, side: Int = fieldSide) throws -> [SIMD3<Double>] {
        Fixtures.linear(try EmulsionTestCase.kernels.grainNoise(CGRect(x: 0, y: 0, width: side, height: side), seed: seed))
    }

    private static func channel(_ v: [SIMD3<Double>], _ c: Int) -> [Double] { v.map { $0[c] } }

    // MARK: Noise field

    /// Per channel on 1 MP: mean, variance, cross-channel and lag-1 correlation. Measured (seed 3):
    /// |mean| ≤ 0.0008, variance 0.998–1.001, excess kurtosis −0.299…−0.304 (a sum of four uniforms:
    /// −0.3), |correlations| ≤ 0.002.
    @Test func noiseIsZeroMeanUnitVarianceAndIndependent() throws {
        let field = try noise(seed: 3)
        let side = Self.fieldSide
        for c in 0..<3 {
            let v = Self.channel(field, c)
            let sd = GrainMeasurement.standardDeviation(v)
            let kurtosis = GrainMeasurement.excessKurtosis(v)
            let lagX = GrainMeasurement.lagCorrelation(v, width: side, height: side, dx: 1, dy: 0)
            let lagY = GrainMeasurement.lagCorrelation(v, width: side, height: side, dx: 0, dy: 1)
            print(
                String(
                    format: "GRAIN noise ch%d mean %.5f var %.5f kurtosis %.4f lag-x %.5f lag-y %.5f", c,
                    GrainMeasurement.mean(v), sd * sd, kurtosis, lagX, lagY))
            #expect(abs(GrainMeasurement.mean(v)) < 0.01)
            #expect(abs(sd * sd - 1) < 0.02)
            #expect(abs(kurtosis) < 0.5, "close to Gaussian")
            #expect(abs(lagX) < 0.02 && abs(lagY) < 0.02)
        }
        for (a, b) in [(0, 1), (0, 2), (1, 2)] {
            let r = GrainMeasurement.correlation(Self.channel(field, a), Self.channel(field, b))
            print(String(format: "GRAIN noise corr ch%d-ch%d %.5f", a, b, r))
            #expect(abs(r) < 0.02)
        }
    }

    /// Same seed, same field; neighbouring whole seeds 0…100 and a half seed give independent
    /// fields (the hash once dropped the seed's integer part). Measured worst |r| 0.0047.
    @Test func noiseIsDeterministicAndDecorrelatedAcrossSeeds() throws {
        let side = 256
        func pattern(_ seed: Double) throws -> [Double] { try noise(seed: seed, side: side).flatMap { [$0.x, $0.y, $0.z] } }
        let three = try pattern(3)
        #expect(try pattern(3) == three, "same seed, same grain")
        let half = try pattern(3.5)
        #expect(half != three)
        #expect(abs(GrainMeasurement.correlation(three, half)) < 0.05)
        var previous = try pattern(0)
        var worst = 0.0
        for n in 1...100 {
            let next = try pattern(Double(n))
            worst = max(worst, abs(GrainMeasurement.correlation(previous, next)))
            previous = next
        }
        print(String(format: "GRAIN seeds 0…100 worst neighbour |r| %.4f", worst))
        #expect(worst < 0.05, "neighbouring seeds 0…100 must be independent")
    }

    /// The noise is integer arithmetic up to its last multiply, so it is the same on every device:
    /// the GPU field equals this CPU copy of the kernel (pcg4d) to float rounding. The float hash it
    /// replaced differed from its own CPU copy in 38,223 of 38,400 pixels (one fused multiply-add
    /// changes most of its values), so a GPU that rounds differently would have rendered other grain.
    /// Measured: worst 0 (bit-identical) on 256 × 256 including negative coordinates, seeds 0, 3, 1023.
    @Test(arguments: [0.0, 3, 1023])
    func noiseIsTheSameOnEveryDevice(seed: Double) throws {
        let extent = CGRect(x: -128, y: -64, width: 256, height: 256)
        let gpu = Fixtures.linear(try EmulsionTestCase.kernels.grainNoise(extent, seed: seed))
        var worst = 0.0
        for row in 0..<256 {
            for column in 0..<256 {
                let cpu = Self.referenceNoise(x: Int32(column) - 128, y: Int32(row) - 64, seed: Float(seed))
                worst = max(worst, simd_reduce_max(simd_abs(SIMD3<Double>(cpu) - gpu[row * 256 + column])))
            }
        }
        print(String(format: "GRAIN noise GPU vs integer reference, seed %.0f: worst %.3g", seed, worst))
        #expect(worst <= 1e-6)
    }

    /// The kernel `grainNoise` at pixel (x, y), computed on the CPU.
    private static func referenceNoise(x: Int32, y: Int32, seed: Float) -> SIMD3<Float> {
        func pcg4d(_ input: SIMD4<UInt32>) -> SIMD4<UInt32> {
            var v = input &* 1_664_525 &+ 1_013_904_223
            func mix() {
                v.x &+= v.y &* v.w
                v.y &+= v.z &* v.x
                v.z &+= v.x &* v.y
                v.w &+= v.y &* v.z
            }
            mix()
            v ^= v &>> 16
            mix()
            return v
        }
        return SIMD3(
            (0..<3).map { c in
                let a = pcg4d(SIMD4(UInt32(bitPattern: x), UInt32(bitPattern: y), seed.bitPattern, UInt32(c))) &>> 10
                return (Float(2 * (a.x + a.y + a.z + a.w) + 4) / 4_194_304 - 4) * (3 / Float(4)).squareRoot()
            })
    }

    /// White at the pixel scale: the radially averaged periodogram (10 bands to 0.5 cycles/pixel) is
    /// flat. Measured: every band within 1.7% of the variance, all channels.
    @Test func noiseSpectrumIsWhite() throws {
        let field = try noise(seed: 3)
        for c in 0..<3 {
            let spectrum = GrainMeasurement.radialPowerSpectrum(Self.channel(field, c), width: Self.fieldSide, height: Self.fieldSide)
            #expect(spectrum.count >= 8)
            let worst = spectrum.map { abs($0.power - 1) }.max() ?? .infinity
            print(
                String(format: "GRAIN spectrum ch%d worst band deviation %.4f: ", c, worst)
                    + spectrum.map { String(format: "%.3f", $0.power) }.joined(separator: " "))
            #expect(worst < 0.1)
        }
    }

    // MARK: Datasheet table and Selwyn scaling

    /// The engine's table is the digitized one, and it reproduces Kodak's trace at camera stops
    /// −4…+4 within the interpolation error (minimax fit ≤ 5.2%). Measured worst: 3.6%.
    @Test func tableMatchesTheDigitizedDatasheet() throws {
        let reference = try ColorReferences.granularity()
        #expect(Grain.logExposureKnots == reference.engineTable.logExposureKnots)
        #expect(Grain.sigmaD48Red == reference.engineTable.sigmaD48um.red)
        #expect(Grain.sigmaD48Green == reference.engineTable.sigmaD48um.green)
        #expect(Grain.sigmaD48Blue == reference.engineTable.sigmaD48um.blue)
        for (i, knot) in Grain.logExposureKnots.enumerated() {
            let expected = SIMD3(Grain.sigmaD48Red[i], Grain.sigmaD48Green[i], Grain.sigmaD48Blue[i])
            #expect(simd_reduce_max(simd_abs(Grain.sigmaD48(logExposure: SIMD3(repeating: knot)) - expected)) < 1e-12)
        }
        var worst = 0.0
        for stop in [-4, -2, 0, 2, 4] {
            let sigma = Grain.sigmaD48(logExposure: SIMD3(repeating: Double(stop) * log10(2.0)))
            for c in 0..<3 {
                let trace = try #require(reference.sigmaAtCameraStops[c]["\(stop)"])
                let error = abs(sigma[c] / trace - 1)
                worst = max(worst, error)
                #expect(error <= 0.06, "layer \(c) at \(stop) stops: \(sigma[c]) vs \(trace)")
            }
        }
        print(String(format: "GRAIN table vs trace at camera stops: worst %.4f", worst))
    }

    /// Selwyn's law against the Boolean-model reference (opaque 0.5 µm grains at D 0.3, 0.8, 1.5):
    /// the reference's σ at 48 µm, scaled to square pixels, is within 10% of its simulated pixel σ
    /// (measured 1.0–4.1% high for p ≥ 6.2 µm, 6.7–9.8% high at 3.1 µm); noise power per area σ²p²
    /// equals the reference's W(0) (measured within 0.6%). The frame width gives the reference's pitches.
    @Test func selwynScalingMatchesTheBooleanReference() throws {
        let reference = try ColorReferences.grainBooleanModel()
        for density in reference.densities {
            let sigma48 = density.aperture48um.sigmaDLinearized.value
            for pixel in density.pixels {
                let predicted = sigma48 * Grain.selwynScale(pixelPitchMicrometres: pixel.sideUm)
                let ratio = predicted / pixel.sigmaDLinearized.value
                print(String(format: "GRAIN Selwyn D %.1f p %.1f µm: predicted/simulated %.4f", density.targetDensity, pixel.sideUm, ratio))
                #expect(abs(ratio - 1) <= 0.10, "D \(density.targetDensity), p \(pixel.sideUm) µm: \(ratio)")
                if pixel.sideUm >= 6 { #expect(abs(ratio - 1) <= 0.05) }
                let pitch = FilmLook.micrometresPerPixel(longEdge: Double(pixel.pixelCountAcrossFrame))
                #expect(abs(pitch / pixel.exactPitchUm - 1) < 1e-4)
            }
            let p = 6.2
            let power = pow(sigma48 * Grain.selwynScale(pixelPitchMicrometres: p), 2) * p * p
            let w0 = density.spectrum.w0SimulatedPlateau.value
            print(String(format: "GRAIN W(0) D %.1f: σ²p² %.5f vs reference %.5f", density.targetDensity, power, w0))
            #expect(abs(power / w0 - 1) <= 0.10)
        }
    }

    // MARK: Through the print

    /// Flat neutral patches at 1600×1200, grain 1: rendered display σ per channel matches the Swift
    /// mirror's Monte Carlo prediction within 5% (measured worst 0.3%), and follows the table: it is
    /// not a constant across exposure.
    @Test func displayGrainFollowsTheMirroredFilm() throws {
        let (w, h) = (1600, 1200)
        var rendered: [SIMD3<Double>] = []
        for stops in [-4.0, -2, 0, 2, 4] {
            let sd = GrainMeasurement.channelSD(
                GrainMeasurement.linearCrop(
                    try EmulsionTestCase.render(GrainMeasurement.flat(stops: stops, width: w, height: h), Self.adjustments(grain: 1)),
                    size: 512))
            let predicted = GrainMeasurement.predictedDisplaySD(stops: stops, amount: 1, longEdge: Double(w))
            print(
                String(
                    format: "GRAIN %+.0f stops display σ codes rendered %.3f %.3f %.3f predicted %.3f %.3f %.3f",
                    stops, sd.x, sd.y, sd.z, predicted.x, predicted.y, predicted.z))
            #expect(simd_reduce_max(simd_abs(sd / predicted - 1)) <= 0.05, "\(stops) stops: \(sd) vs \(predicted)")
            rendered.append(sd)
        }
        let green = rendered.map(\.y)
        #expect((green.max() ?? 0) / (green.min() ?? 1) > 1.5, "grain changes with exposure: \(green)")
    }

    /// Preview and export carry the same grain (the issue's acceptance). The 4032×3024 render is
    /// reduced to each preview size by an area (box) average. For a whole-number scale the box is
    /// Selwyn's aperture; at fractional scales its partial pixels keep only scale²·Σw² (0.81, 0.75,
    /// 0.62) of a white field's variance relative to a continuous aperture, so the ratio is taken
    /// with that known factor removed. Measured at 1179, 1600, 2556 px: 1.005, 1.004, 1.000; against
    /// Selwyn's prediction from the full-size σ 1.007, 1.006, 1.004 (raw box 1.11, 1.16, 1.27;
    /// Lanczos 1.11, 1.14, 1.12: it keeps only 76–80% of a white field's variance).
    @Test func previewAndExportCarryMatchingGrain() throws {
        for r in try GrainMeasurement.previewExport(renderer) {
            print(
                String(
                    format: "GRAIN preview %d: area white %.4f (raw %.4f, factor %.4f) Lanczos %.4f Selwyn %.4f", r.previewLongEdge,
                    r.areaRatioWhite, r.areaRatio, r.areaWhiteVarianceFactor, r.lanczosRatio, r.selwynRatio))
            #expect((0.9...1.1).contains(r.areaRatioWhite), "\(r.previewLongEdge): \(r.areaRatioWhite)")
            #expect((0.9...1.1).contains(r.selwynRatio), "\(r.previewLongEdge): \(r.selwynRatio)")
        }
    }

    /// The blue layer is the grainiest at mid-gray, by the table's ratio (σ_B/σ_G ≈ 2.0, σ_B/σ_R ≈ 2.1),
    /// measured as σ·SD(n) on the noise field; the displayed grain has colour (channels not perfectly
    /// correlated; measured r(R,G) 0.10, r(G,B) 0.17 at 1600 px).
    @Test func blueLayerIsGrainiestAndDisplayGrainHasChroma() throws {
        let field = try noise(seed: 3)
        let sigma = Grain.densitySigma(logExposure: .zero, amount: 1, longEdge: 1600)
        let measured = sigma * SIMD3((0..<3).map { GrainMeasurement.standardDeviation(Self.channel(field, $0)) })
        for c in 0..<2 {
            let expected = sigma.z / sigma[c]
            #expect(expected > 1.5)
            #expect(abs(measured.z / measured[c] / expected - 1) < 0.02)
        }
        let display = GrainMeasurement.linearCrop(
            try EmulsionTestCase.render(GrainMeasurement.flat(stops: 0, width: 1600, height: 1200), Self.adjustments(grain: 1)), size: 512
        ).map(GrainMeasurement.codes)
        let (rg, gb) = (
            GrainMeasurement.correlation(Self.channel(display, 0), Self.channel(display, 1)),
            GrainMeasurement.correlation(Self.channel(display, 1), Self.channel(display, 2))
        )
        print(
            String(
                format: "GRAIN mid-gray σ_B/σ_G %.3f σ_B/σ_R %.3f; display r(R,G) %.4f r(G,B) %.4f",
                measured.z / measured.y, measured.z / measured.x, rg, gb))
        #expect(rg < 0.95 && gb < 0.95)
    }

    // MARK: Off and mean

    /// Grain 0 skips the generator and adds exactly zero density: renders are identical whatever the
    /// seed, scene- and display-referred, and grain changes only the edited print of a photo.
    @Test func grainZeroIsTheCleanRender() throws {
        let scene = SceneFixtures.chart24()
        let picture = DisplayFixtures.proofChart()
        for (image, contract) in [(scene, InputContract.sceneReferred), (picture, .displayReferred)] {
            let source = contract == .displayReferred ? try renderer.developer.sceneFromDisplay(image).image : image
            let clean = EmulsionTestCase.codes(try EmulsionTestCase.render(source, Self.adjustments(grain: 0, seed: 3), contract: contract))
            #expect(
                EmulsionTestCase.codes(try EmulsionTestCase.render(source, Self.adjustments(grain: 0, seed: 77), contract: contract))
                    == clean)
            #expect(EmulsionTestCase.codes(try EmulsionTestCase.render(source, Self.adjustments(grain: 1), contract: contract)) != clean)
        }
    }

    /// A density fluctuation printed through a nonlinear film moves the mean slightly. Measured at
    /// 1600 px, grain 1 (display luma, codes): −3 stops +0.086, mid-gray −0.002, +3 stops −0.078.
    @Test(arguments: [-3.0, 0, 3])
    func grainBarelyMovesTheMean(_ stops: Double) throws {
        let scene = GrainMeasurement.flat(stops: stops, width: 1600, height: 1200)
        func meanLuma(_ grain: Double) throws -> Double {
            GrainMeasurement.mean(
                GrainMeasurement.linearCrop(try EmulsionTestCase.render(scene, Self.adjustments(grain: grain)), size: 512).map {
                    EmulsionTestCase.luma(GrainMeasurement.codes($0))
                })
        }
        let shift = try meanLuma(1) - meanLuma(0)
        print(String(format: "GRAIN mean shift at %+.0f stops: %+.4f codes", stops, shift))
        #expect(abs(shift) < 1)
    }
}

/// `References/granularity.json` (written by `Tools/grain-reference/granularity`): the digitized
/// datasheet granularity of the stock the engine's table comes from.
struct GrainReference: Decodable, Sendable {
    struct Layers: Decodable, Sendable { let red, green, blue: [Double] }
    struct EngineTable: Decodable, Sendable {
        let logExposureKnots: [Double]
        let sigmaD48um: Layers
        // convertFromSnakeCase reads "sigma_d_48um" as "sigmaD48Um".
        private enum CodingKeys: String, CodingKey {
            case logExposureKnots
            case sigmaD48um = "sigmaD48Um"
        }
    }
    struct Stock: Decodable, Sendable {
        let engineTable: EngineTable
        let sigmaDAtCameraStops: [String: [String: Double]]
    }
    let stocks: [String: Stock]

    static let stock = "kodak-vision3-250d-5207"

    let engineTable: EngineTable
    /// Kodak's trace at camera stops, per layer (red, green, blue), keyed by stop ("-4"…"4").
    let sigmaAtCameraStops: [[String: Double]]

    private enum CodingKeys: String, CodingKey { case stocks }

    init(from decoder: any Decoder) throws {
        stocks = try decoder.container(keyedBy: CodingKeys.self).decode([String: Stock].self, forKey: .stocks)
        guard let stock = stocks[Self.stock] else { throw CocoaError(.coderValueNotFound) }
        engineTable = stock.engineTable
        sigmaAtCameraStops = ["R", "G", "B"].map { stock.sigmaDAtCameraStops[$0] ?? [:] }
    }

    /// `References/grain-boolean-model.json` (written by `Tools/grain-reference/boolean-model`).
    struct BooleanModel: Decodable, Sendable {
        struct Estimate: Decodable, Sendable { let value: Double }
        struct Aperture: Decodable, Sendable { let sigmaDLinearized: Estimate }
        struct Pixel: Decodable, Sendable {
            let sideUm: Double
            let exactPitchUm: Double
            let pixelCountAcrossFrame: Int
            let sigmaDLinearized: Estimate
        }
        struct Spectrum: Decodable, Sendable { let w0SimulatedPlateau: Estimate }
        struct Density: Decodable, Sendable {
            let targetDensity: Double
            let aperture48um: Aperture
            let pixels: [Pixel]
            let spectrum: Spectrum
            private enum CodingKeys: String, CodingKey {
                case targetDensity
                case aperture48um = "aperture48Um"
                case pixels, spectrum
            }
        }
        let densities: [Density]
    }
}
