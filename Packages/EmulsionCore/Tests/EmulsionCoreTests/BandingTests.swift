import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Smooth ramps must render without visible steps (MOV-146). The detector is `Banding`; its
/// thresholds come from the measurements quoted there.
struct BandingTests {
    // MARK: The detector

    /// Display P3 encoded gray, `count` samples from `low` to `high`.
    private static func grayRamp(_ low: Double, _ high: Double, count: Int) -> [SIMD3<Double>] {
        (0..<count).map { SIMD3(repeating: low + (high - low) * Double($0) / Double(count - 1)) }
    }

    @Test func smoothRampHasNoBands() {
        #expect(Banding.bands(in: Self.grayRamp(0.02, 0.98, count: 400)).isEmpty)
    }

    @Test func aStepThatStandsOutIsABand() {
        var ramp = Self.grayRamp(0.2, 0.6, count: 200)
        for i in 100..<ramp.count { ramp[i] += SIMD3(repeating: 0.03) }
        let bands = Banding.bands(in: ramp)
        #expect(bands.map(\.index) == [99], "\(bands)")
    }

    /// Equal coarse steps (an 8-bit source lifted by an edit) are quantisation, not a band.
    @Test func evenlyCoarseRampIsNotABand() {
        let ramp = Self.grayRamp(0.2, 0.6, count: 21)
        #expect(Banding.Profile(ramp).steps.allSatisfy { $0 > Banding.minimumVisibleStep })
        #expect(Banding.bands(in: ramp).isEmpty)
    }

    /// Plateaus joined by visible jumps (contouring): every jump is a band.
    @Test func contouringIsBanding() {
        let ramp = Self.grayRamp(0.2, 0.6, count: 400).map { ($0 / 0.02).rounded(.down) * 0.02 }
        let bands = Banding.bands(in: ramp)
        #expect(bands.count >= 18, "\(bands.count) of 20 jumps")
    }

    @Test func aLightnessFoldIsABand() {
        var ramp = Self.grayRamp(0.2, 0.6, count: 200)
        ramp[120] = ramp[110]
        #expect(Banding.bands(in: ramp).contains { $0.index == 119 && $0.lightnessChange < 0 })
    }

    // MARK: MOV-25 near-black banding

    private struct Reference: Decodable {
        struct Ramp: Decodable {
            let name: String
            let banded: [[UInt16]]
            let fixed: [[UInt16]]
        }
        let ramps: [Ramp]

        static func load() throws -> Reference {
            let url = try #require(Bundle.module.url(forResource: "banding-mov25", withExtension: "json", subdirectory: "References"))
            return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        }
    }

    private static func encoded(_ codes: [[UInt16]]) -> [SIMD3<Double>] {
        codes.map { SIMD3(Double($0[0]), Double($0[1]), Double($0[2])) / RegressionImage.maxCode }
    }

    /// The renders that banded in MOV-25 (frozen in `References/banding-mov25.json`): display black
    /// estimated at −9 stops on the fitted negative separates codes 0 and 1 under a lifting edit.
    /// Measured here: gray ΔE00 8.26 at 4.24× its neighbours, blue 8.37 at 4.20×; the shipped
    /// −6-stop floor gives 2.06 at 1.72× and 3.05 at 1.88×.
    @Test func detectsTheMOV25NearBlackBanding() throws {
        for ramp in try Reference.load().ramps {
            let banded = Banding.bands(in: Self.encoded(ramp.banded))
            #expect(banded.map(\.index) == [0], "\(ramp.name) at −9 stops: \(banded)")
            let fixed = Banding.bands(in: Self.encoded(ramp.fixed))
            #expect(fixed.isEmpty, "\(ramp.name) at −6 stops: \(fixed)")
        }
    }

    // MARK: The engine's ramps

    private static func adjusted(_ change: (inout Adjustments) -> Void) -> Adjustments {
        var a = Adjustments.neutral
        change(&a)
        return a
    }

    /// Point edits only: grain would add steps of its own, and halation needs area.
    static let edits: [(name: String, adjustments: Adjustments)] = [
        ("neutral", .neutral), ("exposure +2", adjusted { $0.exposure = 2 }), ("exposure +3", adjusted { $0.exposure = 3 }),
        ("exposure −2", adjusted { $0.exposure = -2 }), ("shadows +1", adjusted { $0.shadows = 1 }),
        ("exposure +2, shadows +1", adjusted { ($0.exposure, $0.shadows) = (2, 1) }),
        ("highlights −1", adjusted { $0.highlights = -1 }), ("color +0.7", adjusted { $0.color = 0.7 }),
    ]

    /// Scene-referred ramps: 1,024 samples evenly spaced in stops around mid-gray.
    private static func sceneRamp(stops: ClosedRange<Double>, tint: SIMD3<Float>) -> CIImage {
        let count = 1024
        return Fixtures.row(
            (0..<count).map { i in
                let stops = stops.lowerBound + (stops.upperBound - stops.lowerBound) * Double(i) / Double(count - 1)
                return tint * Float(0.18 * pow(2, stops))
            }, space: SceneFixtures.linear)
    }

    /// 8-bit Display P3 ramps, one code per sample, through the display-referred path.
    private static func displayRamp(codes: ClosedRange<Int>, tint: SIMD3<Float>) -> CIImage {
        Fixtures.row(codes.map { tint * Float($0) / 255 }, space: DisplayFixtures.displayP3)
    }

    struct Ramp: Sendable, CustomTestStringConvertible {
        let name: String
        let image: @Sendable () -> CIImage
        var contract = InputContract.sceneReferred
        var testDescription: String { name }
    }

    static let ramps: [Ramp] = [
        Ramp(name: "scene dark gray, −10…−2 stops", image: { sceneRamp(stops: -10...(-2), tint: [1, 1, 1]) }),
        Ramp(name: "scene dark blue, −10…−2 stops", image: { sceneRamp(stops: -10...(-2), tint: [0.35, 0.5, 1]) }),
        Ramp(name: "scene bright gray, +1…+8 stops", image: { sceneRamp(stops: 1...8, tint: [1, 1, 1]) }),
        Ramp(name: "scene bright orange, +1…+8 stops", image: { sceneRamp(stops: 1...8, tint: [1, 0.55, 0.25]) }),
        Ramp(name: "display gray, codes 0…255", image: { displayRamp(codes: 0...255, tint: [1, 1, 1]) }, contract: .displayReferred),
        Ramp(name: "display blue, codes 0…48", image: { displayRamp(codes: 0...48, tint: [0.4, 0.5, 1]) }, contract: .displayReferred),
    ]

    /// Measured on an M4 Max (macOS 27.2): no ramp has a band. The largest step is ΔE00 4.80 at
    /// 2.62× its neighbours (display blue, shadows +1, codes 0→1); scene ramps stay under 0.16.
    @Test(arguments: ramps)
    func rampsRenderWithoutBands(_ ramp: Ramp) throws {
        let renderer = VisualRegression.renderer
        let image = ramp.image()
        let negative =
            ramp.contract == .displayReferred
            ? try renderer.developer.sceneFromDisplay(image) : Negative(image: image, contract: .sceneReferred)
        for edit in Self.edits {
            let rendered = RegressionImage(rendering: try renderer.render(negative, edit.adjustments))
            let bands = Banding.bands(in: rendered.encoded)
            #expect(bands.isEmpty, "\(ramp.name), \(edit.name): \(bands)")
        }
    }
}
