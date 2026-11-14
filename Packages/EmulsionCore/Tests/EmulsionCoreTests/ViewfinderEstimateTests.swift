import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// The viewfinder's approximate preview inverse (`Developer.viewfinderNegative(from:)`) against
/// the exact per-pixel estimate (`sceneFromDisplay`). Both estimates are printed through the
/// absolute film system with the default tone and no grain or halation; the error is OKLab
/// ΔE×100 (`Fixtures.deltaE`) on that print.
struct ViewfinderEstimateTests {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }

    @Test func grayRampPrintsLikeTheExactEstimate() throws {
        let error = try printedError(Self.grayRamp)
        #expect(error.max <= Self.maxDeltaE)
        #expect(error.mean <= Self.meanDeltaE)
    }

    @Test func saturatedColorsPrintLikeTheExactEstimate() throws {
        let error = try printedError(Self.saturated)
        #expect(error.max <= Self.maxDeltaE)
        #expect(error.mean <= Self.meanDeltaE)
    }

    @Test func saturatedGradientPrintsLikeTheExactEstimate() throws {
        let error = try printedError(Self.hueSweep)
        #expect(error.max <= Self.maxDeltaE)
        #expect(error.mean <= Self.meanDeltaE)
    }

    /// The estimate itself on the gray ramp (white reaches about +4 stops, so values above 1 must
    /// survive the curves filter), in stops where the display is above the print's black, and in
    /// encoded display value below it.
    @Test func grayEstimateMatchesInStopsAboveThePrintsBlack() throws {
        let fast = Fixtures.encodedFloats(renderer.developer.viewfinderNegative(from: Self.grayRamp).image, space: SceneFixtures.linearP3)
        let exact = Fixtures.encodedFloats(try renderer.developer.sceneFromDisplay(Self.grayRamp).image, space: SceneFixtures.linearP3)
        let model = FilmLook.stock
        // Display values at or below the print's black F_n(floor) (= softEnds.compress(0)) are squeezed onto its flat toe,
        // where an exposure is ill-conditioned, so there the estimate is compared after printing it back to display.
        let black = model.softEnds.compress(0)
        var (maxStops, maxBlackDisplayError) = (0.0, 0.0)
        for (step, (f, e)) in zip(fast, exact).enumerated() {
            if Self.displayLinear(step) > black {
                maxStops = max(maxStops, (0..<3).map { abs(log2(max(f[$0], 1e-9) / max(e[$0], 1e-9))) }.max() ?? 0)
            } else {
                let (a, b) = (model.display(fromSceneEstimate: f), model.display(fromSceneEstimate: e))
                maxBlackDisplayError = max(maxBlackDisplayError, (0..<3).map { abs(Self.encoded(a[$0]) - Self.encoded(b[$0])) }.max() ?? 0)
            }
        }
        #expect(maxStops <= Self.maxStops)
        #expect(maxBlackDisplayError <= Self.maxBlackDisplayError)
        #expect((fast.last?.y ?? 0) > 2, "white keeps its estimate above 1")
    }

    @Test func viewfinderNegativeIsAPreviewEstimate() {
        #expect(renderer.developer.viewfinderNegative(from: Self.grayRamp).contract == .previewEstimate)
    }

    /// Out-of-range display light is clamped to 0…1 first, as the kernel does.
    @Test func outOfRangeLightIsClampedLikeTheKernel() throws {
        let linear = Fixtures.linearSRGB
        let source = Fixtures.row([[1.5, 1.5, 1.5], [-0.2, 0.3, 0.3], [1.4, 0.2, -0.1]], space: linear)
        let error = try printedError(source)
        #expect(error.max <= Self.maxDeltaE)
    }

    /// Translucent pixels: both estimates come back premultiplied by the same alpha.
    @Test func translucentPixelsKeepTheirAlpha() throws {
        let color = CIColor(red: 0.3, green: 0.6, blue: 0.1, alpha: 0.5, colorSpace: Fixtures.linearSRGB)!
        let source = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let fast = Self.rgba(renderer.developer.viewfinderNegative(from: source).image)
        let exact = Self.rgba(try renderer.developer.sceneFromDisplay(source).image)
        #expect(abs(fast.w - exact.w) < 1e-3)
        for c in 0..<3 { #expect(Double(abs(log2(fast[c] / exact[c]))) <= Self.maxStops, "channel \(c)") }
    }

    /// On the CPU: the suite's GPU contexts stay the shared renderer's and the fixtures' (MOV-127).
    private static let alphaReadback = CIContext(options: [.workingColorSpace: Fixtures.linearSRGB, .useSoftwareRenderer: true])

    private static func rgba(_ image: CIImage) -> SIMD4<Float> {
        var pixel = SIMD4<Float>.zero
        alphaReadback.render(image, toBitmap: &pixel, rowBytes: 16, bounds: image.extent, format: .RGBAf, colorSpace: Fixtures.linearSRGB)
        return pixel
    }

    // MARK: Tolerances: twice the worst measured on the Mac (M-series GPU)

    /// Measured max: gray ramp 0.036, primaries/secondaries and patches 0.017, hue sweep 0.026,
    /// out-of-range light 0.007. A visible step is about 1.
    static let maxDeltaE = 0.07
    /// Measured mean: gray ramp 0.0075, saturated 0.0053, hue sweep 0.0060.
    static let meanDeltaE = 0.02
    /// Measured: 0.0026 stops on the gray ramp above the print's black; white 2.8785 against 2.8800.
    /// Below the print's black (the first 119 steps) it misses by up to 0.001 stops.
    static let maxStops = 0.01
    /// Encoded display value (0…1) of the two estimates printed back to display, at or below the
    /// print's black. Measured: 3.9e-5 (0.16 of a 12-bit code).
    static let maxBlackDisplayError = 1.5e-4

    // MARK: Fixtures

    /// Display-linear value of `grayRamp`'s step.
    static func displayLinear(_ step: Int) -> Double { InputColorSpace.displayP3.decode(signal: Double(step) / Double(grayRampSteps - 1)) }

    static func encoded(_ linear: Double) -> Double { Double(Fixtures.encode(Float(linear))) }

    /// 4096 steps of encoded P3 gray: four per table entry, so it samples between them; the
    /// first steps are deep shadows near the −6-stop floor.
    static let grayRampSteps = 4096
    static let grayRamp = Fixtures.row(Fixtures.grayRamp(steps: grayRampSteps), space: DisplayFixtures.displayP3)

    /// P3 primaries and secondaries at several encoded levels, plus the display patches.
    static let saturated: CIImage = {
        let hues: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1], [1, 0, 1], [1, 1, 0]]
        let levels: [Float] = [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 1]
        let colors = hues.flatMap { hue in levels.map { hue * $0 } } + DisplayFixtures.patches.map(\.code)
        return Fixtures.row(colors, space: DisplayFixtures.displayP3)
    }()

    /// Fully saturated P3 hues all the way round, at full and half level.
    static let hueSweep: CIImage = {
        let steps = 720
        let colors = (0..<steps).map { i -> SIMD3<Float> in
            let h = Float(i % 360) / 60
            let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
            let rgb: SIMD3<Float> =
                switch Int(h) {
                case 0: [1, x, 0]
                case 1: [x, 1, 0]
                case 2: [0, 1, x]
                case 3: [0, x, 1]
                case 4: [x, 0, 1]
                default: [1, 0, x]
                }
            return i < 360 ? rgb : rgb * 0.5
        }
        return Fixtures.row(colors, space: DisplayFixtures.displayP3)
    }()

    private func printedError(_ source: CIImage) throws -> (max: Double, mean: Double) {
        let exact = Negative(image: try renderer.developer.sceneFromDisplay(source).image, contract: .sceneReferred)
        let fast = renderer.developer.viewfinderNegative(from: source)
        let a = Fixtures.oklab(try renderer.render(exact, .neutral))
        let b = Fixtures.oklab(try renderer.render(fast, .neutral))
        let errors = zip(a, b).map { Fixtures.deltaE($0, $1) }
        return (errors.max() ?? 0, errors.reduce(0, +) / Double(errors.count))
    }
}
