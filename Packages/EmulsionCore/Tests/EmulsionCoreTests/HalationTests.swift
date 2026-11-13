import CoreImage
import CoreImage.CIFilterBuiltins
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Halation v2 (MOV-32, MOV-102): base-reflection light added to layer exposure, linear in exposure.
/// The glow G is measured on its own (`Kernels.halationGlow`); the layer exposure it gives is
/// E′ = `Halation.exposureWithHalation`, which the film kernels apply (checked against the mirror).
struct HalationTests {
    static func adjustments(_ amount: Double = 1, _ backing: AntihalationBacking = .unbacked) -> Adjustments {
        var a = Adjustments.neutral
        (a.halation, a.backing) = (amount, backing)
        return a
    }

    private static func codes(_ scene: CIImage, _ a: Adjustments) throws -> [SIMD3<Double>] {
        EmulsionTestCase.codes(try EmulsionTestCase.render(scene, a))
    }

    /// The glow G per pixel: blurred layer exposure before the exposure control, unclamped.
    static func glow(_ scene: CIImage, saturation: Double = 1) throws -> [SIMD3<Double>] {
        Fixtures.linear(try EmulsionTestCase.kernels.halationGlow(of: scene, model: FilmLook.stock, saturation: saturation))
    }

    /// Layer exposure E per pixel, as the film kernels compute it: max(sensitivity · saturated light
    /// after the exposure control, 0).
    static func layerExposure(_ scene: CIImage, _ a: Adjustments) -> [SIMD3<Double>] {
        let model = FilmLook.stock
        return Fixtures.encodedFloats(scene, space: SceneFixtures.linearP3).map {
            simd_max(model.sensitivity * model.saturated($0 * pow(2, a.exposure), a.printSaturation), .zero)
        }
    }

    /// Added layer exposure ΔE = E′ − E per pixel, E′ from the measured glow.
    static func addedExposure(_ scene: CIImage, _ a: Adjustments) throws -> [SIMD3<Double>] {
        let k = Halation.layerReturn(amount: a.halation, backing: a.backing)
        return zip(layerExposure(scene, a), try glow(scene, saturation: a.printSaturation)).map { exposure, glow in
            Halation.exposureWithHalation(exposure, glow: simd_max(glow, .zero) * pow(2, a.exposure), layerReturn: k) - exposure
        }
    }

    /// k / (1 + k) per layer: the share of a layer's exposure the glow replaces.
    static func share(_ backing: AntihalationBacking = .unbacked) -> SIMD3<Double> {
        let k = Halation.layerReturn(amount: 1, backing: backing)
        return k / (1 + k)
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
    /// is unchanged everywhere, borders and corners included. Measured worst: 0.0001 codes, every size.
    /// Odd sizes too: their halving is extended by the edge pixel and reflected half a pixel inside
    /// (`mirroredPyramid`); 255 × 171 is a thumbnail-sized frame, 801 × 601 one whose blurs are all halved.
    @Test(
        arguments: [SIMD3<Float>(0.18, 0.18, 0.18), SIMD3(16, 16, 16), SIMD3(0.6, 0.2, 0.05), SIMD3(0.05, 0.3, 2)],
        [
            SIMD2(300, 200), SIMD2(255, 171), SIMD2(801, 601),
        ])
    func uniformFieldsAreUnchanged(_ light: SIMD3<Float>, _ size: SIMD2<Int>) throws {
        let field = Fixtures.image(width: size.x, height: size.y, space: SceneFixtures.linearP3) { _, _ in light }
        let plain = try Self.codes(field, Self.adjustments(0))
        var worst = 0.0
        for backing in AntihalationBacking.allCases {
            for amount in [0.35, 1] {
                let difference = Self.maxDifference(try Self.codes(field, Self.adjustments(amount, backing)), plain)
                #expect(difference <= 0.5, "\(light) \(size) \(backing) \(amount): \(difference) codes")
                worst = max(worst, difference)
            }
        }
        print(String(format: "HALATION uniform %@ %dx%d: worst %.4f codes", "\(light)", size.x, size.y, worst))
    }

    /// Halation 0 adds exactly nothing, for both contracts and every backing: the film kernels get
    /// k = 0, and with k = 0 any glow drops out (here a bright one), so the render is the clean one.
    @Test(arguments: [InputContract.sceneReferred, .displayReferred])
    func halationZeroIsTheCleanRender(_ contract: InputContract) throws {
        let renderer = EmulsionTestCase.sharedRenderer
        let point = SceneFixtures.highlightPoint(size: 200)
        let scene = contract == .displayReferred ? try renderer.developer.sceneFromDisplay(DisplayFixtures.proofChart()).image : point
        let negative = Negative(image: scene, contract: contract)
        var a = Self.adjustments(0, .remJet)
        (a.exposure, a.color, a.warmth) = (0.7, 0.6, -0.3)
        let clean = EmulsionTestCase.codes(try renderer.render(negative, a))
        for backing in AntihalationBacking.allCases {
            a.backing = backing
            #expect(EmulsionTestCase.codes(try renderer.render(negative, a)) == clean, "\(backing)")
        }
        let bright = CIImage(color: CIColor(red: 16, green: 8, blue: 4)).cropped(to: scene.extent)
        let black = CIImage(color: .black).cropped(to: scene.extent)
        let withGlow = try renderer.filmPrint(negative, glow: bright, noise: black, a)
        #expect(EmulsionTestCase.codes(withGlow.cropped(to: scene.extent)) == clean)
    }

    // MARK: Exposure order (MOV-102)

    /// Halation is linear in exposure, so doubling the scene light and opening one stop give the
    /// same picture. Measured: 0.0 codes; the luminance-threshold halation it replaced failed by 33–37.
    @Test(arguments: ["highlight-point", "edge"], [AntihalationBacking.unbacked, .remJet])
    func exposureCommutesWithHalation(_ sceneName: String, _ backing: AntihalationBacking) throws {
        let scene = sceneName == "edge" ? SceneFixtures.edge() : SceneFixtures.highlightPoint(size: 800)
        let doubled = Self.adjustments(1, backing)
        var exposed = doubled
        exposed.exposure = 1
        let worst = Self.maxDifference(try Self.codes(Self.scaled(scene, by: 2), doubled), try Self.codes(scene, exposed))
        #expect(worst <= 1, "max difference \(worst) display codes")
    }

    // MARK: Layers

    /// Light reaches the base through the red layer: a blue source (P3 blue primary) of the same
    /// luminance as a red one adds < 20% of its red-layer exposure, and no layer below the yellow
    /// filter passes blue light back, so blue-layer exposure never rises. Measured: blue/red −0.001
    /// (the blue source exposes the red layer less than the background); blue rise 0 (k is 0 for blue).
    @Test func blueLightBarelyReachesTheRedLayer() throws {
        let size = 400
        let radius: Float = 6
        let (red, blue) = Self.equalLuminanceRedAndBlue(red: 16)
        let fromRed = try Self.addedExposure(SceneFixtures.disc(size: size, radius: radius, light: red), Self.adjustments())
        let fromBlue = try Self.addedExposure(SceneFixtures.disc(size: size, radius: radius, light: blue), Self.adjustments())
        let ring = (Int(radius) + 4...Int(radius) + 30).map { EmulsionTestCase.pixel(x: size / 2 + $0, y: size / 2, width: size) }
        let redGlow = ring.map { fromRed[$0].x }.reduce(0, +)
        let blueGlow = ring.map { fromBlue[$0].x }.reduce(0, +)
        #expect(redGlow > 0)
        #expect(blueGlow < 0.2 * redGlow, "blue/red \(blueGlow / redGlow)")
        let blueRise = (fromRed + fromBlue).map(\.z).max() ?? 0
        #expect(blueRise <= 1e-3, "blue layer rose by \(blueRise)")
    }

    /// The P3 red primary at `red` and the P3 blue primary of the same luminance.
    static func equalLuminanceRedAndBlue(red: Float) -> (red: SIMD3<Float>, blue: SIMD3<Float>) {
        let weights = SIMD3<Float>(FilmModel.p3Luminance)
        return (SIMD3(red, 0, 0), SIMD3(0, 0, red * weights.x / weights.z))
    }

    // MARK: Colour

    /// The glow is added to layer exposure after the Color control's saturation, so Color does not
    /// re-tint it: a neutral highlight's halation renders the same at Color −1, 0 and +1 (measured
    /// worst 9e-5 codes), and around a coloured source the added exposure of every layer follows the
    /// mirror (the source's layer exposure at that saturation, convolved with the profile), within
    /// the radial profile's 1.5% of the peak (measured worst: 0.0011 at −1 and +1).
    @Test func colorDoesNotRetintTheGlow() throws {
        let neutral = HalationDisc(size: 400)
        var looks: [[SIMD3<Double>]] = []
        for color in [-1.0, 0, 1] {
            var a = Self.adjustments()
            a.color = color
            looks.append(try Self.codes(neutral.scene, a))
        }
        #expect(Self.maxDifference(looks[0], looks[1]) <= 0.01 && Self.maxDifference(looks[2], looks[1]) <= 0.01)
        #expect(Self.maxDifference(looks[1], try Self.codes(neutral.scene, Self.adjustments(0))) > 3, "the glow shows")

        let disc = HalationDisc(size: 800, light: SIMD3(8, 4, 2))
        for color in [-1.0, 1] {
            var a = Self.adjustments()
            a.color = color
            let profile = try radialProfile(disc, a)
            print(String(format: "HALATION Color %+.0f: worst deviation %.4f of the peak", color, profile))
            #expect(profile <= 0.015, "Color \(color): worst deviation \(profile) of the peak")
        }
    }

    /// The film kernel exposes each layer to E′ = (E + k·G·2^EV)/(1 + k), as the Swift mirror does,
    /// at Color −1 and +1 and an exposure edit (mild colours and glows, so the output gamut fit stays
    /// inactive). Measured: ≤ 0.0007 codes.
    @Test(arguments: [-1.0, 1])
    func filmKernelAddsTheGlowAsTheMirror(color: Double) throws {
        var colors: [SIMD3<Float>] = []
        var glows: [SIMD3<Float>] = []
        var seed: UInt32 = 5
        func next() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24)
        }
        for _ in 0..<200 {
            let level = 0.18 * pow(2, 6 * next() - 4)
            colors.append(level * (0.75 + 0.25 * SIMD3(next(), next(), next())))
            glows.append(level * (0.5 + SIMD3(next(), next(), next())))
        }
        var a = Self.adjustments()
        (a.color, a.exposure) = (color, 0.7)
        let scene = Fixtures.row(colors, space: SceneFixtures.linearP3)
        let glow = Fixtures.row(glows, space: SceneFixtures.linear)
        let black = CIImage(color: .black).cropped(to: scene.extent)
        let printed = try EmulsionTestCase.sharedRenderer.filmPrint(
            Negative(image: scene, contract: .sceneReferred), glow: glow, noise: black, a)
        let gpu = EmulsionTestCase.codes(printed)
        let k = Halation.layerReturn(amount: a.halation, backing: a.backing)
        let gain = pow(2, a.exposure)
        var worst = 0.0
        for i in colors.indices {
            let reference = FilmLook.stock.render(
                SIMD3<Double>(colors[i]) * gain, saturation: a.printSaturation, glow: SIMD3<Double>(glows[i]) * gain, layerReturn: k,
                grain: .zero)
            let codes = SIMD3((0..<3).map { Fixtures.encode(min(1, max(0, reference[$0]))) * 255 })
            worst = max(worst, simd_reduce_max(simd_abs(gpu[i] - codes)))
        }
        print(String(format: "HALATION film kernel vs mirror, Color %+.0f: worst %.4f codes", color, worst))
        #expect(worst <= 0.6)
    }

    // MARK: Kernel

    /// The mixture's encircled energy against the exact single-bounce profile
    /// (`References/halation-kernel.json`, from `Tools/halation-kernel`). Measured: 0.0616.
    @Test func kernelMatchesTheDerivedProfile() throws {
        let reference = try ColorReferences.halationKernel()
        let fit = reference.recommended
        #expect(fit.kind == "one_negative" && fit.count == 3)
        for i in 0..<3 {
            #expect(abs(fit.weights[i] - Halation.weights[i]) <= 1e-7)
            #expect(abs(fit.sigmasT[i] - Halation.sigmasInBaseThicknesses[i]) <= 1e-7)
        }
        #expect(abs(reference.geometry.returnedFraction - Halation.baseReturnFraction) <= 5e-4)
        #expect(abs(Halation.weights.sum() - 1) <= 1e-6, "unit volume")
        let exact = try reference.irradianceProfile()
        let deviations = zip(exact.rT, exact.encircled).map { abs(Halation.encircledEnergy(radiusInBaseThicknesses: $0) - $1) }
        let worst = deviations.max() ?? 1
        #expect(worst <= 0.07, "max encircled-energy deviation \(worst)")
    }

    /// Added red-layer exposure around a small disc against the mixture convolved with the disc,
    /// from thumbnail sizes (256, 512: `ThumbnailCache`) to 1600 px and an odd size, compared at the
    /// same frame fractions (resolution independence). Deviation is relative to the reference peak
    /// outside the disc. Measured: 0.0115 (256), 0.0055 (384), 0.0026 (512), 0.0010 (800, 801),
    /// 0.0047 (1600); before narrow blurs used exact taps and the near-cancelling pair shared a level,
    /// 0.030 (256) and 0.039 (512).
    @Test(arguments: [256, 384, 512, 800, 801, 1600])
    func glowFollowsTheKernelAtAnySize(_ size: Int) throws {
        let profile = try radialProfile(HalationDisc(size: size), Self.adjustments())
        print(String(format: "HALATION size %d: worst deviation %.4f of the peak", size, profile))
        #expect(profile <= 0.015, "size \(size): worst deviation \(profile) of the peak")
    }

    /// Light moves, it is not created: over the frame the added red-layer exposure sums to ~0; at
    /// the source centre E′ = (E + k·G) / (1 + k) with G from the mixture convolved with the disc.
    /// Measured: net 0.00 of 522.6 moved; centre 10.158 vs 10.158.
    @Test func halationMovesExposure() throws {
        let size = 800
        let disc = HalationDisc(size: size)
        let added = try Self.addedExposure(disc.scene, Self.adjustments())
        let net = added.map(\.x).reduce(0, +)
        let moved = added.map { abs($0.x) }.reduce(0, +)
        #expect(abs(net) <= 0.01 * moved, "net \(net) of \(moved) moved")
        print(String(format: "HALATION net %.2f of %.1f moved", net, moved))

        let k = Halation.layerReturn(amount: 1, backing: .unbacked)
        let centre = SIMD2(Double(size / 2), Double(size / 2))
        let exposure = disc.discExposure()
        let measured = exposure.x + added[EmulsionTestCase.pixel(x: size / 2, y: size / 2, width: size)].x
        let expected = Halation.exposureWithHalation(exposure, glow: disc.glow(at: centre), layerReturn: k).x
        #expect(abs(measured - expected) <= 0.002 * exposure.x, "centre \(measured) vs \(expected)")
        print(String(format: "HALATION centre %.3f vs %.3f", measured, expected))
    }

    /// The reflection asks Core Image only for the source pixels it reads (asking for the whole
    /// image kept a full-resolution intermediate at 48 MP, review B6): every pixel centre of a
    /// requested rect, reflected as the kernel `mirroredEdges` does, lies in the rect it asks for,
    /// for whole and half-pixel (halved odd) mirrors and rects inside, across and beyond the edges.
    @Test(arguments: [CGRect(x: 0, y: 0, width: 40, height: 30), CGRect(x: 0, y: 0, width: 20.5, height: 15.5)])
    func reflectionAsksOnlyForWhatItReads(_ mirror: CGRect) {
        func reflect(_ v: Double, _ start: Double, _ size: Double) -> Double {
            let period = 2 * size
            let u = v - start
            let m = u - period * (u / period).rounded(.down)
            return start + (m > size ? period - m : m)
        }
        for rect in [
            CGRect(x: 5, y: 5, width: 10, height: 10), CGRect(x: -12, y: -3, width: 20, height: 8),
            CGRect(x: 30, y: 20, width: 25, height: 20), CGRect(x: -50, y: -40, width: 200, height: 150),
            CGRect(x: 55, y: 2, width: 6, height: 4),
        ] {
            let source = Halation.mirroredSource(of: rect, in: mirror)
            #expect(source.width * source.height < mirror.width * mirror.height || rect.width > mirror.width, "\(rect)")
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let read = CGPoint(
                        x: reflect(Double(x) + 0.5, mirror.minX, mirror.width), y: reflect(Double(y) + 0.5, mirror.minY, mirror.height))
                    #expect(source.contains(read), "\(rect) pixel (\(x), \(y)) reads \(read) outside \(source)")
                }
            }
        }
    }

    // MARK: Backing

    /// Measured ratio none/rem-jet 12.99494 vs 12.99495 implied.
    @Test func backingScalesTheGlowAsItsReturnImplies() throws {
        let scene = HalationDisc(size: 400).scene
        func glow(_ backing: AntihalationBacking) throws -> Double {
            try Self.addedExposure(scene, Self.adjustments(1, backing)).map { max($0.x, 0) }.reduce(0, +)
        }
        let ratio = try glow(.unbacked) / glow(.remJet)
        let implied = Self.share(.unbacked).x / Self.share(.remJet).x
        #expect(abs(ratio / implied - 1) <= 0.001, "ratio \(ratio), implied \(implied)")
        let undercoat = try Self.codes(scene, Self.adjustments(1, .undercoat))
        #expect(Self.maxDifference(undercoat, try Self.codes(scene, Self.adjustments(1, .remJet))) == 0)
    }

    // MARK: Display

    /// Next to a neutral highlight the glow is red-dominant; far away nothing changes. Measured
    /// 10 px outside (unbacked, amount 1): +(193.5, 92.3, 13.3) codes; far: < 1e-4.
    @Test func glowIsRedAndLocal() throws {
        let point = SceneFixtures.highlightPoint(size: 800)
        let with = try Self.codes(point, Self.adjustments())
        let without = try Self.codes(point, Self.adjustments(0))
        let ring = EmulsionTestCase.pixel(x: 400 + 12 + 10, y: 400, width: 800)  // 10 px outside the source edge
        let delta = with[ring] - without[ring]
        print(String(format: "HALATION 10 px outside: +(%.1f, %.1f, %.1f) codes", delta.x, delta.y, delta.z))
        #expect(delta.x > delta.y && delta.y > delta.z && delta.z >= -0.5, "\(delta)")
        #expect(delta.x > 3, "visible \(delta)")
        let far = EmulsionTestCase.pixel(x: 20, y: 20, width: 800)
        #expect(simd_reduce_max(simd_abs(with[far] - without[far])) <= 0.5)
    }

    // MARK: Measurement

    /// Measured vs reference added exposure of the red and green layers at frame fractions
    /// 0.008…0.08 from the centre (outside the disc); the worst deviation is relative to the
    /// reference peak of each layer. The blue layer gets none.
    private func radialProfile(_ disc: HalationDisc, _ a: Adjustments) throws -> Double {
        let added = try Self.addedExposure(disc.scene, a)
        #expect(added.allSatisfy { $0.z == 0 }, "blue layer")
        let share = Self.share(a.backing)
        let background = SIMD3(repeating: disc.backgroundExposure)
        let c = disc.size / 2
        var worst = 0.0
        for layer in 0..<2 {
            var rows: [(measured: Double, reference: Double)] = []
            for step in 0...36 {
                let r = Int(((0.008 + 0.002 * Double(step)) * Double(disc.size)).rounded())
                let points = [(c + r, c), (c - r, c), (c, c + r), (c, c - r)]
                let measured = points.map { added[EmulsionTestCase.pixel(x: $0.0, y: $0.1, width: disc.size)][layer] }.reduce(0, +) / 4
                let glow = disc.glow(at: SIMD2(Double(c + r), Double(c)), saturation: a.printSaturation)
                rows.append((measured, share[layer] * (glow - background)[layer]))
            }
            let peak = rows.map(\.reference).max() ?? 1
            worst = max(worst, rows.map { abs($0.measured - $0.reference) / peak }.max() ?? 1)
        }
        return worst
    }
}

/// A small bright disc (frame fraction 0.005 radius) on a dark neutral background, and its reference
/// glow: the mixture convolved with the disc's pixels (4×4 samples per pixel).
struct HalationDisc {
    static let radiusFrame = 0.005
    static let background: Float = 0.02
    let size: Int
    /// The disc's light (linear Display P3).
    var light = SIMD3<Float>(repeating: 16)
    var radius: Float { Float(Self.radiusFrame * Double(size)) }
    var scene: CIImage { SceneFixtures.disc(size: size, radius: radius, light: light, background: Self.background) }
    /// Layer exposure of the disc at `saturation` (the Color control).
    func discExposure(saturation: Double = 1) -> SIMD3<Double> {
        let model = FilmLook.stock
        return simd_max(model.sensitivity * model.saturated(SIMD3<Double>(light), saturation), .zero)
    }
    /// Layer exposure of the neutral background: the sensitivity rows sum to 1.
    var backgroundExposure: Double { Double(Self.background) }

    /// The glow G per layer at pixel centre `point`.
    func glow(at point: SIMD2<Double>, saturation: Double = 1) -> SIMD3<Double> {
        let background = SIMD3(repeating: backgroundExposure)
        return background + (discExposure(saturation: saturation) - background) * discShare(at: point)
    }

    /// The share of the light returned at pixel centre `point` that comes from the disc, with
    /// `kernel(r)` in h·t² per base thickness.
    func discShare(at point: SIMD2<Double>, kernel: (Double) -> Double = { Halation.profile(radiusInBaseThicknesses: $0) }) -> Double {
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
        return inside
    }
}

/// `References/halation-kernel.json`, written by `Tools/halation-kernel/halation_kernel.py`.
struct HalationReference: Decodable, Sendable {
    struct Fit: Decodable, Sendable {
        let kind: String
        let count: Int
        let weights: [Double]
        let sigmasT: [Double]
    }
    struct Geometry: Decodable, Sendable { let returnedFraction: Double }
    struct Profile: Decodable, Sendable {
        let rT: [Double]
        let hT2: [Double]
        let encircled: [Double]
    }
    struct Model: Decodable, Sendable {
        let absorptionModel: String
        let profile: Profile
    }
    let geometry: Geometry
    let recommended: Fit
    let models: [Model]

    func irradianceProfile() throws -> Profile {
        try #require(models.first { $0.absorptionModel == "irradiance" }).profile
    }
}
