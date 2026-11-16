import CoreImage
import CoreImage.CIFilterBuiltins
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Halation v2 (MOV-32, MOV-102): base-reflection light added to layer exposure, linear in exposure.
struct HalationTests {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    private static let sensitivity = FilmLook.stock.sensitivity

    private static func adjustments(_ amount: Double = 1, _ backing: AntihalationBacking = .none) -> Adjustments {
        var a = Adjustments.neutral
        (a.halation, a.backing) = (amount, backing)
        return a
    }

    private func codes(_ scene: CIImage, _ a: Adjustments) throws -> [SIMD3<Double>] {
        EmulsionTestCase.codes(try renderer.render(Negative(image: scene, contract: .sceneReferred), a))
    }

    /// Unclamped layer exposure (sensitivity · linear P3 scene light) after halation.
    private func layerExposure(_ scene: CIImage, _ a: Adjustments) throws -> [SIMD3<Double>] {
        Fixtures.encodedFloats(try renderer.sceneWithHalation(scene, a), space: SceneFixtures.linearP3).map { Self.sensitivity * $0 }
    }

    /// Added layer exposure ΔE = E′ − E per pixel.
    private func addedExposure(_ scene: CIImage, _ a: Adjustments) throws -> [SIMD3<Double>] {
        zip(try layerExposure(scene, a), try layerExposure(scene, Self.adjustments(0))).map { $0 - $1 }
    }

    private static func scaled(_ scene: CIImage, by factor: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = scene
        filter.rVector = CIVector(x: factor, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: factor, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: factor, w: 0)
        return filter.outputImage?.cropped(to: scene.extent) ?? scene
    }

    private static func maxDifference(_ a: [SIMD3<Double>], _ b: [SIMD3<Double>]) -> Double {
        zip(a, b).map { simd_reduce_max(simd_abs($0 - $1)) }.max() ?? 0
    }

    // MARK: Uniform fields

    /// Film speed is defined on uniform patches, which include their own halation: a uniform field
    /// is unchanged everywhere, borders and corners included. Measured worst: 0.02 codes (16.0, none, 1).
    @Test(arguments: [SIMD3<Float>(0.18, 0.18, 0.18), SIMD3(16, 16, 16), SIMD3(0.6, 0.2, 0.05), SIMD3(0.05, 0.3, 2)])
    func uniformFieldsAreUnchanged(_ light: SIMD3<Float>) throws {
        let field = Fixtures.image(width: 300, height: 200, space: SceneFixtures.linearP3) { _, _ in light }
        let plain = try codes(field, Self.adjustments(0))
        for backing in AntihalationBacking.allCases {
            for amount in [0.35, 1] {
                let worst = Self.maxDifference(try codes(field, Self.adjustments(amount, backing)), plain)
                #expect(worst <= 0.5, "\(light) \(backing) \(amount): \(worst) codes")
            }
        }
    }

    // MARK: Exposure order (MOV-102)

    /// Halation is linear in exposure, so doubling the scene light and opening one stop give the
    /// same picture. Measured: 0.0 codes; the luminance-threshold halation it replaced failed by 33–37.
    @Test(arguments: ["highlight-point", "edge"], [AntihalationBacking.none, .remJet])
    func exposureCommutesWithHalation(_ sceneName: String, _ backing: AntihalationBacking) throws {
        let scene = sceneName == "edge" ? SceneFixtures.edge() : SceneFixtures.highlightPoint(size: 800)
        let doubled = Self.adjustments(1, backing)
        var exposed = doubled
        exposed.exposure = 1
        let worst = Self.maxDifference(try codes(Self.scaled(scene, by: 2), doubled), try codes(scene, exposed))
        #expect(worst <= 1, "max difference \(worst) display codes")
    }

    // MARK: Layers

    /// Light reaches the base through the red layer: a blue source (P3 blue primary) of the same
    /// luminance as a red one adds < 20% of its red-layer exposure, and no layer below the yellow
    /// filter passes blue light back, so blue-layer exposure never rises. Measured: blue/red −0.001
    /// (the blue source exposes the red layer less than the background); blue rise 6e-5.
    @Test func blueLightBarelyReachesTheRedLayer() throws {
        let size = 400
        let radius: Float = 6
        let redLevel: Float = 16
        let red = SceneFixtures.disc(size: size, radius: radius, light: SIMD3(redLevel, 0, 0))
        let blue = SceneFixtures.disc(size: size, radius: radius, light: SIMD3(0, 0, redLevel * 0.2289746 / 0.0792869))
        let fromRed = try addedExposure(red, Self.adjustments())
        let fromBlue = try addedExposure(blue, Self.adjustments())
        let ring = (Int(radius) + 4...Int(radius) + 30).map { EmulsionTestCase.pixel(x: size / 2 + $0, y: size / 2, width: size) }
        let redGlow = ring.map { fromRed[$0].x }.reduce(0, +)
        let blueGlow = ring.map { fromBlue[$0].x }.reduce(0, +)
        #expect(redGlow > 0)
        #expect(blueGlow < 0.2 * redGlow, "blue/red \(blueGlow / redGlow)")
        let blueRise = (fromRed + fromBlue).map(\.z).max() ?? 0
        #expect(blueRise <= 1e-3, "blue layer rose by \(blueRise)")
    }

    // MARK: Kernel

    /// The mixture's encircled energy against the exact single-bounce profile
    /// (`References/halation-kernel.json`, from `Tools/halation-kernel`). Measured: 0.0616.
    @Test func kernelMatchesTheDerivedProfile() throws {
        let reference = try HalationReference.load()
        let fit = reference.recommended
        #expect(fit.kind == "one_negative" && fit.count == 3)
        for i in 0..<3 {
            #expect(abs(fit.weights[i] - Halation.weights[i]) <= 1e-7)
            #expect(abs(fit.sigmasT[i] - Halation.sigmasInBaseThicknesses[i]) <= 1e-7)
        }
        #expect(abs(reference.geometry.returnedFraction - FilmLook.halationReturnFraction) <= 5e-4)
        #expect(abs(Halation.weights.sum() - 1) <= 1e-6, "unit volume")
        let exact = try reference.irradianceProfile()
        let deviations = zip(exact.rT, exact.encircled).map { abs(Halation.encircledEnergy(radiusInBaseThicknesses: $0) - $1) }
        let worst = deviations.max() ?? 1
        #expect(worst <= 0.07, "max encircled-energy deviation \(worst)")
    }

    /// Added red-layer exposure around a small disc against the mixture convolved with the disc,
    /// at two image sizes, compared at the same frame fractions (resolution independence).
    /// Deviation is relative to the reference peak outside the disc. Measured: 0.012 (800), 0.011 (1600).
    @Test(arguments: [800, 1600])
    func glowFollowsTheKernelAtAnySize(_ size: Int) throws {
        let profile = try radialProfile(size: size)
        #expect(profile.worst <= 0.03, "size \(size): worst deviation \(profile.worst) of the peak")
    }

    /// Light moves, it is not created: over the frame the added red-layer exposure sums to ~0; at
    /// the source centre E′ = (E + k·G) / (1 + k) with G from the mixture convolved with the disc.
    /// Measured: net −1.4 of 522 moved; centre 10.167 vs 10.158.
    @Test func halationMovesExposure() throws {
        let size = 800
        let disc = HalationDisc(size: size)
        let added = try addedExposure(disc.scene, Self.adjustments())
        let net = added.map(\.x).reduce(0, +)
        let moved = added.map { abs($0.x) }.reduce(0, +)
        #expect(abs(net) <= 0.01 * moved, "net \(net) of \(moved) moved")

        let k = Halation.layerReturn(amount: 1, backing: .none)
        let centre = EmulsionTestCase.pixel(x: size / 2, y: size / 2, width: size)
        let measured = try layerExposure(disc.scene, Self.adjustments())[centre].x
        let glow = disc.redExposure(glowAt: SIMD2(Double(size / 2), Double(size / 2)))
        let expected = Halation.exposureWithHalation(SIMD3(repeating: disc.redExposure), glow: SIMD3(repeating: glow), layerReturn: k).x
        #expect(abs(measured - expected) <= 0.002 * disc.redExposure, "centre \(measured) vs \(expected)")
    }

    // MARK: Backing

    /// Measured ratio none/rem-jet 12.99494 vs 12.99495 implied.
    @Test func backingScalesTheGlowAsItsReturnImplies() throws {
        let scene = HalationDisc(size: 400).scene
        func glow(_ backing: AntihalationBacking) throws -> Double {
            try addedExposure(scene, Self.adjustments(1, backing)).map { max($0.x, 0) }.reduce(0, +)
        }
        let share = { (b: AntihalationBacking) in
            let k = Halation.layerReturn(amount: 1, backing: b).x
            return k / (1 + k)
        }
        let ratio = try glow(.none) / glow(.remJet)
        let implied = share(.none) / share(.remJet)
        #expect(abs(ratio / implied - 1) <= 0.001, "ratio \(ratio), implied \(implied)")

        let undercoat = try layerExposure(scene, Self.adjustments(1, .undercoat))
        #expect(Self.maxDifference(undercoat, try layerExposure(scene, Self.adjustments(1, .remJet))) == 0)
        #expect(try renderer.sceneWithHalation(scene, Self.adjustments(0)) === scene, "halation 0 is a no-op")
    }

    // MARK: Display

    /// Next to a neutral highlight the glow is red-dominant; far away nothing changes. Measured
    /// 10 px outside (unbacked, amount 1): +(195.8, 134.1, 19.1) codes; far: < 1e-4.
    @Test func glowIsRedAndLocal() throws {
        let point = SceneFixtures.highlightPoint(size: 800)
        let with = try codes(point, Self.adjustments())
        let without = try codes(point, Self.adjustments(0))
        let ring = EmulsionTestCase.pixel(x: 400 + 12 + 10, y: 400, width: 800)  // 10 px outside the source edge
        let delta = with[ring] - without[ring]
        #expect(delta.x > delta.y && delta.y > delta.z && delta.z >= -0.5, "\(delta)")
        #expect(delta.x > 3, "visible \(delta)")
        let far = EmulsionTestCase.pixel(x: 20, y: 20, width: 800)
        #expect(simd_reduce_max(simd_abs(with[far] - without[far])) <= 0.5)
    }

    // MARK: Measurement

    /// Measured vs reference added red-layer exposure at frame fractions 0.008…0.08 from the centre.
    private func radialProfile(size: Int) throws -> (worst: Double, rows: [(frame: Double, measured: Double, reference: Double)]) {
        let disc = HalationDisc(size: size)
        let added = try addedExposure(disc.scene, Self.adjustments())
        let k = Halation.layerReturn(amount: 1, backing: .none).x
        let share = k / (1 + k)
        let c = size / 2
        var rows: [(Double, Double, Double)] = []
        for step in 0...36 {
            let frame = 0.008 + 0.002 * Double(step)
            let r = Int((frame * Double(size)).rounded())
            let points = [(c + r, c), (c - r, c), (c, c + r), (c, c - r)]
            let measured = points.map { added[EmulsionTestCase.pixel(x: $0.0, y: $0.1, width: size)].x }.reduce(0, +) / 4
            let glow = disc.redExposure(glowAt: SIMD2(Double(c + r), Double(c)))
            rows.append((Double(r) / Double(size), measured, share * (glow - disc.backgroundRedExposure)))
        }
        let peak = rows.map(\.2).max() ?? 1
        return (rows.map { abs($0.1 - $0.2) }.max().map { $0 / peak } ?? 1, rows)
    }
}

/// A small bright neutral disc (frame fraction 0.005 radius) and its reference glow: the mixture
/// convolved with the disc's pixels (4×4 samples per pixel).
struct HalationDisc {
    static let radiusFrame = 0.005
    static let level: Float = 16
    static let background: Float = 0.02
    let size: Int
    var radius: Float { Float(Self.radiusFrame * Double(size)) }
    var scene: CIImage { SceneFixtures.disc(size: size, radius: radius, light: SIMD3(repeating: Self.level), background: Self.background) }
    /// Red-layer exposure of a neutral: rows of the sensitivity sum to 1.
    var redExposure: Double { Double(Self.level) }
    var backgroundRedExposure: Double { Double(Self.background) }

    /// Blurred red-layer exposure G at pixel centre `point`, with `kernel(r)` in h·t² per base thickness.
    func redExposure(glowAt point: SIMD2<Double>, kernel: (Double) -> Double = { Halation.profile(radiusInBaseThicknesses: $0) }) -> Double
    {
        let perBase = Halation.pixelsPerBaseThickness(longEdge: Double(size))
        let c = size / 2
        let reach = Int(radius) + 1
        let samples = 4
        var inside = 0.0
        for y in c - reach...c + reach {
            for x in c - reach...c + reach where hypot(Float(x - c), Float(y - c)) < radius {
                for sy in 0..<samples {
                    for sx in 0..<samples {
                        let sub = SIMD2(
                            Double(x) + (Double(sx) + 0.5) / Double(samples) - 0.5, Double(y) + (Double(sy) + 0.5) / Double(samples) - 0.5)
                        let r = simd_distance(sub, point) / perBase
                        inside += kernel(r) / (perBase * perBase) / Double(samples * samples)
                    }
                }
            }
        }
        return backgroundRedExposure + (redExposure - backgroundRedExposure) * inside
    }
}

/// `References/halation-kernel.json`, written by `Tools/halation-kernel/halation_kernel.py`.
struct HalationReference: Decodable {
    struct Fit: Decodable {
        let kind: String
        let count: Int
        let weights: [Double]
        let sigmasT: [Double]
    }
    struct Geometry: Decodable { let returnedFraction: Double }
    struct Profile: Decodable {
        let rT: [Double]
        let hT2: [Double]
        let encircled: [Double]
    }
    struct Model: Decodable {
        let absorptionModel: String
        let profile: Profile
    }
    let geometry: Geometry
    let recommended: Fit
    let models: [Model]

    func irradianceProfile() throws -> Profile {
        try #require(models.first { $0.absorptionModel == "irradiance" }).profile
    }

    static func load() throws -> HalationReference {
        let url = try #require(Bundle.module.url(forResource: "halation-kernel", withExtension: "json", subdirectory: "References"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }
}
