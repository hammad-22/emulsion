import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Display-referred sources (JPEG, HEIC, Rec.709, Display P3) get a bounded scene estimate and are
/// printed relative to themselves (docs/ENGINE.md, "Input contracts"). Codes are encoded Display
/// P3 ×255 before 8-bit rounding; negatives are materialized (half float) as in the app, except
/// where a test compares against the Swift mirror.
struct DisplayReferredTests {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    private let model = FilmLook.stock

    // MARK: Zero edits reproduce the photo

    /// Measured: 0.057 codes at worst.
    @Test func grayCodesRoundTripWithinOneCode() throws {
        let out = try renderedCodes(grayRamp())
        for code in 0..<256 {
            for c in 0..<3 { #expect(abs(out[code][c] - Double(code)) <= 1, "code \(code) channel \(c): \(out[code][c])") }
        }
    }

    /// Measured: |ΔL| ≤ 1.2e-4 and hue ≤ 0.03°. Chroma is kept (ratio 1.000) below 85% of the P3
    /// boundary; above it the output gamut fit (`fitP3`) compresses it, to 0.943 at the primaries.
    @Test func saturatedColorsKeepHueAndLightness() throws {
        let source = Fixtures.row(DisplayFixtures.patches.map(\.code), space: DisplayFixtures.displayP3)
        let input = Fixtures.oklab(source)
        let output = Fixtures.oklab(try renderer.render(try developed(source), .neutral))
        for (i, patch) in DisplayFixtures.patches.enumerated() {
            #expect(Fixtures.hueDifference(input[i], output[i]) <= 5, "\(patch.name) hue")
            #expect(abs(output[i].x - input[i].x) <= 0.02, "\(patch.name) lightness")
            #expect(Fixtures.chroma(output[i]) / Fixtures.chroma(input[i]) >= 0.94, "\(patch.name) chroma")
        }
    }

    // MARK: Edits

    /// Measured at −3 EV: steps 0.18…2.22 codes; codes 248…255 → 155.1…170.3.
    @Test func pullingExposureKeepsTheTopCodesApart() throws {
        var a = Adjustments.neutral
        a.exposure = -3
        let green = try renderedCodes(grayRamp(), a).map(\.y)
        let steps = zip(green.dropFirst(), green).map { $0 - $1 }
        #expect(steps[247...].allSatisfy { $0 <= 3 }, "codes 248…255 steps \(Array(steps[247...]))")
        #expect(steps.allSatisfy { $0 > 0 && $0 <= 3 }, "ramp steps \(steps.min() ?? 0)…\(steps.max() ?? 0)")
    }

    /// Black stays black; every other code darkens at each stop down (measured: by ≥ 0.054 codes).
    @Test func exposureDownDarkensEveryGrayCode() throws {
        var previous = try renderedCodes(grayRamp()).map(\.y)
        for stops in [-1.0, -2, -3] {
            var a = Adjustments.neutral
            a.exposure = stops
            let out = try renderedCodes(grayRamp(), a).map(\.y)
            #expect(out[0] <= previous[0] + 1e-3)
            #expect((1..<256).allSatisfy { out[$0] < previous[$0] }, "\(stops) stops")
            previous = out
        }
    }

    /// Measured at Color −1 (saturation 0.2): red → (245, 180, 181), blue → (129, 130, 229).
    @Test func desaturatingAPrimaryRaisesItsZeroChannels() throws {
        var a = Adjustments.neutral
        a.color = -1
        let primaries: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        let out = try renderedCodes(Fixtures.row(primaries, space: DisplayFixtures.displayP3), a)
        for (i, primary) in primaries.enumerated() {
            for c in 0..<3 where primary[c] == 0 { #expect(out[i][c] > 100, "primary \(i) channel \(c): \(out[i][c])") }
        }
    }

    /// Stepping exposure up and down from zero changes every channel by nearly the same factor
    /// (log-slope in linear P3): no slope jump where the edit changes direction. The asymmetry the
    /// film's own curvature gives shrinks in proportion to the step; a slope jump does not shrink at
    /// all. So halving the step must about halve the asymmetry, and at a hundredth of a stop it stays
    /// within 4%. Measured (worst channel): 4.0% at a fiftieth, 1.0% at a hundredth; at most 0.0019
    /// above half the fiftieth's (the first patch's red). The lift before MOV-25's fix jumped by
    /// (1 − g)²/g, up to 7% here; the two-branch formula before it by 12.9%.
    @Test func exposureResponseIsSmoothThroughZeroEdits() throws {
        let patches: [SIMD3<Float>] = [[0.2, 0.5, 1], [0.3, 0.7, 0.3], [0.9, 0.3, 0.2], [0.6, 0.45, 0.35], [0.3, 0.35, 0.75]]
        let negative = try developed(Fixtures.row(patches, space: DisplayFixtures.displayP3))
        func out(_ stops: Double) throws -> [SIMD3<Double>] {
            var a = Adjustments.neutral
            a.exposure = stops
            return Fixtures.encodedFloats(try renderer.render(negative, a), space: SceneFixtures.linearP3)
        }
        let zero = try out(0)
        /// (rise − fall) / mean of the two, per patch and channel, for a step of `stops`.
        func asymmetry(_ stops: Double) throws -> [[Double]] {
            let (down, up) = (try out(-stops), try out(stops))
            return patches.indices.map { i in
                (0..<3).map { c in
                    let (rise, fall) = (log(up[i][c] / zero[i][c]), log(zero[i][c] / down[i][c]))
                    return (rise - fall) / ((rise + fall) / 2)
                }
            }
        }
        let (step, half) = (try asymmetry(Self.smoothnessStep), try asymmetry(Self.smoothnessStep / 2))
        for i in patches.indices {
            for c in 0..<3 {
                let label = "\(patches[i]) channel \(c): \(step[i][c]) at the step, \(half[i][c]) at half"
                #expect(abs(half[i][c]) <= abs(step[i][c]) / 2 + Self.asymmetryNotShrinking, "\(label)")
                #expect(abs(half[i][c]) <= Self.maxAsymmetry, "\(label)")
            }
        }
    }

    /// A fiftieth of a stop; the bound below applies at half of it.
    static let smoothnessStep = 0.02
    static let maxAsymmetry = 0.04
    /// How much of the asymmetry may fail to halve with the step: twice the 0.0019 measured. A slope jump
    /// larger than twice this would fail.
    static let asymmetryNotShrinking = 0.004

    /// The per-channel relative print (`FilmModel.relative`) for a photo darker than its print by g:
    /// zero edits give the photo, the output never goes negative or falls as the edited print rises,
    /// and for g ≥ (3 − √5)/2 the slope is continuous through zero edits; below it, darkening is
    /// never steeper than brightening.
    @Test(arguments: [0, 0.1, 0.3, 0.382, 0.5, 0.72, 0.9])
    func relativePrintIsMonotoneNonNegativeAndSmooth(_ g: Double) {
        let base = 0.4
        let photo = g * base
        func out(_ print: Double) -> Double { FilmModel.relative(print: print, base: base, photo: photo) }
        #expect(abs(out(base) - photo) < 1e-15)
        var previous = -Double.infinity
        for step in 0...400 {
            let value = out(Double(step) / 200 * base)
            #expect(value >= 0 && value >= previous - 1e-15, "print \(Double(step) / 200 * base): \(value)")
            previous = value
        }
        let h = 1e-7
        let (rising, falling) = ((out(base + h) - photo) / h, (photo - out(base - h)) / h)
        if g >= (3 - 5.0.squareRoot()) / 2 {
            #expect(abs(rising - falling) <= 1e-6, "slopes \(rising), \(falling)")
        } else {
            #expect(falling >= -1e-9 && falling <= rising + 1e-9, "slopes \(rising), \(falling)")
        }
    }

    /// Lifting edits keep adjacent 8-bit codes near black together: display black's estimate sits
    /// where the print still responds (`FilmLook.displayFloorStops`), not on its flat toe, where
    /// codes 0 and 1 were estimated stops apart. One pixel high, so local tone lifts pointwise (its
    /// most). Measured largest step, at codes 0→1: 4.83 codes at +3 EV, 6.85 at +2 EV with shadows +1
    /// (at a −9-stop floor: 11.36 and 32.19).
    @Test(arguments: [(3.0, 0.0, 5.1), (2, 1, 7.3)])
    func liftingNearBlackKeepsAdjacentCodesTogether(exposure: Double, shadows: Double, maxStep: Double) throws {
        let ramp = Fixtures.row((0...24).map { SIMD3<Float>(repeating: Float($0) / 255) }, space: DisplayFixtures.displayP3)
        var a = Adjustments.neutral
        a.exposure = exposure
        a.shadows = shadows
        let out = try renderedCodes(ramp, a)
        for (code, (next, previous)) in zip(out.dropFirst(), out).enumerated() {
            for c in 0..<3 {
                let step = next[c] - previous[c]
                #expect(step >= 0 && step <= maxStep, "code \(code)→\(code + 1) channel \(c): step \(step)")
            }
        }
    }

    /// Display white is estimated as a +4-stop light, above the halation threshold, so a clipped
    /// white in a photo still glows (as `HalationTests` does for scene light). Measured just
    /// outside the disc: +(9.9, 4.5, 2.2) codes; far away: 0.
    @Test func clippedHighlightsInAPhotoStillGlow() throws {
        let size = 400
        let picture = Fixtures.image(width: size, height: size, space: DisplayFixtures.displayP3) { x, y in
            hypot(Float(x - size / 2), Float(y - size / 2)) < 6 ? SIMD3(repeating: 1) : SIMD3(repeating: 40.0 / 255)
        }
        let negative = try developed(picture)
        var on = Adjustments.neutral
        on.halation = 1
        let with = EmulsionTestCase.codes(try renderer.render(negative, on))
        let without = EmulsionTestCase.codes(try renderer.render(negative, .neutral))
        let ring = EmulsionTestCase.pixel(x: 214, y: 200, width: size)  // ~8 px outside the disc edge
        let delta = with[ring] - without[ring]
        let far = EmulsionTestCase.pixel(x: 20, y: 20, width: size)
        #expect(delta.x > 3, "visible glow \(delta)")
        #expect(delta.x > delta.y * 1.5 && delta.y > delta.z, "red-biased \(delta)")
        #expect(abs(with[far].x - without[far].x) <= 0.5, "glow stays local")
    }

    @Test func halationOnAPhotoStaysFinite() throws {
        var a = Adjustments.neutral
        a.halation = 1
        let out = try renderedCodes(DisplayFixtures.proofChart(), a)
        #expect(out.allSatisfy { code in (0..<3).allSatisfy { code[$0].isFinite && (0...255.01).contains(code[$0]) } })
    }

    // MARK: Scene estimate

    /// Measured: white → 2.879 on every channel (the largest of the cube corners), black → 0.18·2⁻⁶.
    @Test func sceneEstimateIsBounded() throws {
        let corners: [SIMD3<Float>] = (0..<8).map { (corner: Int) -> SIMD3<Float> in
            let red = Float(corner & 1)
            let green = Float((corner >> 1) & 1)
            let blue = Float((corner >> 2) & 1)
            return SIMD3<Float>(red, green, blue)
        }
        let scene = try sceneEstimate(Fixtures.row(corners, space: DisplayFixtures.displayP3))
        let ceiling = 0.18 * pow(2, FilmLook.displayCeilingStops)
        let floor = 0.18 * pow(2, FilmLook.displayFloorStops)
        for c in 0..<3 { #expect(abs(scene[0][c] / floor - 1) <= 0.02, "black \(scene[0][c])") }
        for (corner, s) in zip(corners, scene) {
            #expect((0..<3).allSatisfy { s[$0].isFinite && s[$0] <= ceiling * 1.01 }, "\(corner) → \(s)")
        }
    }

    /// Relative to the largest channel, because the inverse sensitivity mixes channels. Measured:
    /// 8.8e-5 (float32 kernel, 22 bisection steps, vs the double-precision mirror).
    @Test func gpuSceneEstimateMatchesTheSwiftMirror() throws {
        let colors = randomColors(count: 256, lowest: 0, span: 1)
        let gpu = try sceneEstimate(Fixtures.row(colors, space: DisplayFixtures.displayP3))
        for (i, color) in colors.enumerated() {
            let reference = model.sceneEstimate(fromDisplay: linear(color))
            #expect(simd_reduce_max(simd_abs(gpu[i] - reference)) <= 5e-4 * reference.max(), "\(color): \(gpu[i]) vs \(reference)")
        }
    }

    /// Mild chroma keeps the output gamut fit inactive (as in `testGPUMatchesSwiftFilmModel`);
    /// codes 0.25…0.75 at saturation 1.3 already reach it (27 codes). Measured: ≤ 0.002 codes.
    @Test(arguments: Edit.allCases)
    func gpuRelativePrintMatchesTheSwiftMirror(edit: Edit) throws {
        let colors = randomColors(count: 200, lowest: 0.35, span: 0.3)
        let a = edit.adjustments
        let gpu = try renderedCodes(Fixtures.row(colors, space: DisplayFixtures.displayP3), a, materialized: false)
        for (i, color) in colors.enumerated() {
            let estimate = model.sceneEstimate(fromDisplay: linear(color))
            let reference = model.renderRelative(
                estimate: estimate, edited: estimate * pow(2, a.exposure), lights: a.printerLights, saturation: a.printSaturation)
            for c in 0..<3 {
                let code = Double(Fixtures.encode(Float(min(1, max(0, reference[c]))))) * 255
                #expect(abs(gpu[i][c] - code) <= 0.6, "\(edit) color \(i) channel \(c)")
            }
        }
    }

    /// Measured: 3e-16.
    @Test func swiftMirrorInvertsItsSceneEstimate() {
        let levels = [0.0, 0.001, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 1]
        for r in levels {
            for g in levels {
                for b in levels {
                    let display = SIMD3(r, g, b)
                    let back = model.display(fromSceneEstimate: model.sceneEstimate(fromDisplay: display))
                    #expect(simd_reduce_max(simd_abs(back - display)) <= 1e-6, "\(display) → \(back)")
                }
            }
        }
    }

    @Test func softEndsAreWellFormedForTheStock() {
        let ends = model.softEnds
        #expect(ends.kneeLow > model.neutralPrint(0.18 * pow(2, FilmLook.displayFloorStops)))
        #expect(model.neutralPrint(0.18 * pow(2, FilmLook.displayCeilingStops)) > ends.kneeHigh)
        #expect(ends.a > 0)
        #expect(ends.b > 0)
    }

    /// Any scene, however far beyond the floor and ceiling, maps back into display 0…1.
    @Test func sceneEstimateInverseStaysInDisplayRange() {
        var previous = SIMD3<Double>(repeating: -.infinity)
        for stops in stride(from: -20.0, through: 20, by: 0.25) {
            let display = model.display(fromSceneEstimate: SIMD3(repeating: 0.18 * pow(2, stops)))
            for c in 0..<3 { #expect(display[c].isFinite && (0...1).contains(display[c]), "\(stops) stops: \(display)") }
            #expect(all(display .>= previous), "\(stops) stops")
            previous = display
        }
    }

    // MARK: A real JPEG

    /// The kernel input is the same decode, so only half-float storage and float32 math remain.
    /// Measured: 0.068 codes. Mild chroma: near the P3 boundary the output gamut fit lifts a low
    /// channel (up to 10 codes on a 0.15…0.85 gradient).
    @Test func jpegAtZeroEditsMatchesItsOwnDecode() throws {
        let picture = Fixtures.image(width: 64, height: 48, space: DisplayFixtures.displayP3) { x, y in
            SIMD3(0.3 + 0.4 * Float(x) / 63, 0.3 + 0.4 * Float(y) / 47, 0.6 - 0.25 * Float(x + y) / 110)
        }
        let jpeg = try renderer.export(picture, format: .jpeg)
        let reference = EmulsionTestCase.codes(try #require(CIImage(data: jpeg)))
        let out = EmulsionTestCase.codes(try renderer.render(try renderer.materialize(try renderer.developer.develop(jpeg)), .neutral))
        for (o, r) in zip(out, reference) { #expect(simd_reduce_max(simd_abs(o - r)) <= 0.25, "\(o) vs \(r)") }
    }

    // MARK: Helpers

    enum Edit: String, CaseIterable, Sendable {
        case exposureDown2, exposureUp1, warmer, lessColor, moreColor
        var adjustments: Adjustments {
            var a = Adjustments.neutral
            switch self {
            case .exposureDown2: a.exposure = -2
            case .exposureUp1: a.exposure = 1
            case .warmer: a.warmth = 1
            case .lessColor: a.color = -0.5  // saturation 0.6
            case .moreColor: a.color = 0.6  // saturation 1.3
            }
            return a
        }
    }

    private func grayRamp() -> CIImage { Fixtures.row(Fixtures.grayRamp(), space: DisplayFixtures.displayP3) }

    private func developed(_ picture: CIImage, materialized: Bool = true) throws -> Negative {
        let negative = try renderer.developer.sceneFromDisplay(picture)
        return materialized ? try renderer.materialize(negative) : negative
    }

    private func renderedCodes(_ picture: CIImage, _ a: Adjustments = .neutral, materialized: Bool = true) throws -> [SIMD3<Double>] {
        EmulsionTestCase.codes(try renderer.render(try developed(picture, materialized: materialized), a))
    }

    private func sceneEstimate(_ picture: CIImage) throws -> [SIMD3<Double>] {
        Fixtures.encodedFloats(try developed(picture, materialized: false).image, space: SceneFixtures.linearP3)
    }

    /// Display P3 code → display-linear P3.
    private func linear(_ code: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3((0..<3).map { ColorMath.decode(Double(code[$0]), curve: InputColorSpace.displayP3.curve) })
    }

    /// Deterministic P3 codes in `lowest…lowest + span` per channel.
    private func randomColors(count: Int, lowest: Float, span: Float) -> [SIMD3<Float>] {
        var seed: UInt32 = 7
        return (0..<count).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let unit = SIMD3(Float(seed >> 8 & 255), Float(seed >> 16 & 255), Float(seed >> 24)) / 255
            return lowest + span * unit
        }
    }
}
