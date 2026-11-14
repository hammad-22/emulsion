import CoreImage
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

/// The digicam process (MOV-149): GPU against its Swift mirror, the clip and tone curve, output
/// geometry, noise, processing and the residual auto white balance.
struct DigicamTests {
    static var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The process alone: no noise, no processing, as-shot light unknown.
    static let clean: Adjustments = {
        var a = Adjustments.neutral
        a.process = .digicam
        return a
    }()

    static func adjust(_ change: (inout Adjustments) -> Void) -> Adjustments {
        var a = clean
        change(&a)
        return a
    }

    static func render(_ scene: CIImage, _ a: Adjustments, asShot: Double? = nil) throws -> CIImage {
        let negative = Negative(
            image: scene, contract: .sceneReferred, asShotWhiteBalance: asShot.map { CameraWhiteBalance(temperature: $0, tint: 0) })
        return try renderer.render(negative, a)
    }

    /// sRGB code values (0…255, before rounding) of `image`, bottom row first.
    static func codes(_ image: CIImage) -> [SIMD3<Double>] { Fixtures.encodedFloats(image, space: srgb).map { $0 * 255 } }

    static func flat(_ value: Double, width: Int, height: Int) -> CIImage {
        SceneFixtures.flat(Float(value), width: width, height: height)
    }

    /// Rec. 709 luma of sRGB codes.
    static func luma(_ c: SIMD3<Double>) -> Double { (c * SIMD3(0.2126, 0.7152, 0.0722)).sum() }

    static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
    static func sd(_ values: [Double]) -> Double {
        let m = mean(values)
        return (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    /// Pixels of a centred `size` × `size` window of a `width`-wide image (bottom row first).
    static func centre(_ pixels: [SIMD3<Double>], width: Int, height: Int, size: Int) -> [SIMD3<Double>] {
        let (x0, y0) = ((width - size) / 2, (height - size) / 2)
        return (y0..<y0 + size).flatMap { y in (x0..<x0 + size).map { pixels[y * width + $0] } }
    }

    // MARK: Pointwise

    /// Chromatic patches, a gray ramp and over-clip light, in 8 px blocks on a 4:3 frame.
    static let patches: [SIMD3<Double>] =
        SceneFixtures.chart24Patches.map { SIMD3<Double>($0.linear) }
        + stride(from: -8.0, through: 4.0, by: 0.5).map { SIMD3(repeating: 0.18 * pow(2, $0)) }
        + [SIMD3(3, 0.2, 0.05), SIMD3(0.4, 1.6, 0.2), SIMD3(0.3, 0.6, 2.4), SIMD3(-0.01, 0.05, 0.1), SIMD3(1.2, 1.0, 0.9)]
    static let block = 8, columns = 12, rows = 9

    /// GPU float vs the Swift mirror in Double: worst difference, in sRGB-encoded 0…1, at the
    /// centre of each block (corner softness at this size is far below a pixel).
    static let mirrorTolerance = 0.002

    @Test(arguments: [
        clean, adjust { ($0.exposure, $0.warmth, $0.tint, $0.color) = (0.7, 0.4, -0.3, 0.5) },
        adjust { ($0.exposure, $0.warmth, $0.color) = (-1.2, -0.6, -0.7) },
    ])
    func gpuMatchesTheSwiftMirror(_ a: Adjustments) throws {
        let (w, h) = (Self.columns * Self.block, Self.rows * Self.block)
        let scene = Fixtures.image(width: w, height: h, space: SceneFixtures.linear) { x, y in
            SIMD3<Float>(Self.patches[min((y / Self.block) * Self.columns + x / Self.block, Self.patches.count - 1)])
        }
        for asShot in [nil, 3000.0] {
            let pixels = Fixtures.linear(try Self.render(scene, a, asShot: asShot))
            let model = DigicamModel(a, asShotTemperature: asShot)
            var worst = 0.0
            for (index, light) in Self.patches.enumerated() {
                let (x, y) = ((index % Self.columns) * Self.block + Self.block / 2, (index / Self.columns) * Self.block + Self.block / 2)
                let (dx, dy) = (Double(x) + 0.5 - Double(w) / 2, Double(y) + 0.5 - Double(h) / 2)
                let r2 = (dx * dx + dy * dy) / (Double(w * w + h * h) / 4)
                let expected = model.render(light, radiusSquared: r2)
                let gpu = pixels[y * w + x]
                for c in 0..<3 { worst = max(worst, abs(DigicamModel.encode(gpu[c]) - DigicamModel.encode(expected[c]))) }
            }
            #expect(worst <= Self.mirrorTolerance, "asShot \(asShot.map { "\($0)" } ?? "nil"): \(worst)")
        }
    }

    @Test func midGrayLandsOnItsCode() throws {
        let model = DigicamModel(Self.clean, asShotTemperature: nil)
        let x = (0.18 / model.clip - DigicamLook.blackOffset) / (1 - DigicamLook.blackOffset)
        #expect(abs(DigicamModel.encode(model.toneCurve(x)) * 255 - 118) < 1e-9)
        #expect(abs(DigicamModel.encode(model.toneCurve(1)) - 1) < 1e-12, "the clip reaches white")
        // On the GPU, through the white balance's small cool-magenta bias: luma within 1 code.
        let pixels = Self.codes(try Self.render(Self.flat(0.18, width: 40, height: 30), Self.clean))
        let centre = pixels[15 * 40 + 20]
        #expect(abs(Self.luma(centre) - 118) < 1, "\(centre)")
    }

    @Test func lightAboveTheClipIsWhiteInThatChannelAndShiftsHue() throws {
        let sky = SIMD3<Float>(0.3, 0.6, 1.0)
        let scene = Fixtures.image(width: 40, height: 30, space: SceneFixtures.linear) { x, _ in x < 20 ? sky * 0.6 : sky * 2 }
        let image = try Self.render(scene, Self.clean)
        let pixels = Self.codes(image)
        let (dim, bright) = (pixels[15 * 40 + 10], pixels[15 * 40 + 30])
        #expect(bright.z >= 254.99 && bright.z <= 255.0001, "the blue channel clips exactly: \(bright)")
        #expect(bright.x < 240, "red stays below the clip: \(bright)")
        let lab = Fixtures.oklab(image)
        let hueShift = Fixtures.hueDifference(lab[15 * 40 + 10], lab[15 * 40 + 30])
        #expect(hueShift > 10, "per-channel clipping turns the sky toward cyan: \(hueShift)° (dim \(dim), bright \(bright))")
    }

    // MARK: Geometry

    @Test(arguments: [
        (4032, 3024, 2592, 1944), (4032, 2268, 2592, 1944), (3024, 4032, 1944, 2592), (8064, 6048, 2592, 1944),
        (1600, 1200, 1600, 1200), (1600, 900, 1200, 900), (900, 1600, 900, 1200), (2592, 1944, 2592, 1944),
    ])
    func outputIsTheSensorFrame(_ size: (Int, Int, Int, Int)) throws {
        let scene = Self.flat(0.18, width: size.0, height: size.1)
        let rendered = try Self.render(scene, Self.adjust { $0.grain = 0.35 })
        #expect(rendered.extent == CGRect(x: 0, y: 0, width: size.2, height: size.3))
        let moved = scene.transformed(by: CGAffineTransform(translationX: 37, y: -11))
        #expect(try Self.render(moved, Self.clean).extent == rendered.extent, "output at the origin")
    }

    @Test func cropIsCentredAndDownscaleKeepsEdges() throws {
        // 16:9 with a bright column band at the far left and right, which the 4:3 crop removes.
        let scene = Fixtures.image(width: 320, height: 180, space: SceneFixtures.linear) { x, _ in
            x < 40 || x >= 280 ? SIMD3(repeating: 1) : SIMD3(repeating: 0.18)
        }
        let image = try Self.render(scene, Self.clean)
        #expect(image.extent.size == CGSize(width: 240, height: 180))
        let pixels = Self.codes(image)
        #expect(pixels.allSatisfy { $0.y < 125 }, "no band left after the crop")
        // Downscaled from a large source: the edge column is not darkened by transparency.
        let large = try Self.render(Self.flat(0.18, width: 3200, height: 2400), Self.clean)
        let edge = Self.codes(large.cropped(to: CGRect(x: 0, y: 972, width: 2, height: 1)))
        #expect(abs(edge[0].y - edge[1].y) < 1, "\(edge)")
    }

    // MARK: Noise

    @Test func noiseIsDeterministicSeededAndZeroMean() throws {
        let scene = Self.flat(0.09, width: 1200, height: 900)
        func lumas(_ seed: Double, grain: Double = 1) throws -> [Double] {
            let pixels = Self.codes(try Self.render(scene, Self.adjust { ($0.grain, $0.seed) = (grain, seed) }))
            return Self.centre(pixels, width: 1200, height: 900, size: 200).map(Self.luma)
        }
        let three = try lumas(3)
        #expect(try lumas(3) == three, "same seed, same noise")
        #expect(try lumas(4) != three, "different seed, different noise")
        let clean = try lumas(3, grain: 0)
        #expect(try lumas(9, grain: 0) == clean, "no noise at 0, whatever the seed")
        #expect(Self.sd(clean) < Self.sd(three) / 5, "only the vignette's gradient without noise")
        #expect(abs(Self.mean(three) - Self.mean(clean)) < 0.5, "zero-mean within half a code")
    }

    /// Measured on period JPEGs (rough, n = 4): a flat mid-dark patch has a luma σ of about 2 codes.
    /// Rendered as exported (sensor size, default processing, JPEG included).
    static let periodNoiseCodes = 2.0
    static let periodNoiseTolerance = 0.5

    @Test func defaultNoiseMatchesPeriodFiles() throws {
        let a = Self.adjust { ($0.grain, $0.halation, $0.seed) = (DigicamLook.defaultNoise, DigicamLook.defaultProcessing, 5) }
        let image = try Self.render(Self.flat(0.18 / 4, width: 2592, height: 1944), a)
        let pixels = Self.centre(Self.codes(image), width: 2592, height: 1944, size: 256)
        let sigma = Self.sd(pixels.map(Self.luma))
        #expect(abs(sigma - Self.periodNoiseCodes) <= Self.periodNoiseTolerance, "luma σ \(sigma) codes")
    }

    // MARK: Processing

    /// Overshoot of a vertical step edge (scene 0.045 → 0.36) at sensor size, as a fraction of the
    /// step in sRGB codes, on the bright side.
    static func overshoot(processing: Double) throws -> Double {
        let (w, h) = (2592, 1944)
        let scene = Fixtures.image(width: w, height: h, space: SceneFixtures.linear) { x, _ in
            SIMD3(repeating: x < w / 2 ? 0.045 : 0.36)
        }
        let image = try render(scene, adjust { $0.halation = processing })
        let row = codes(image.cropped(to: CGRect(x: w / 2 - 24, y: h / 2, width: 48, height: 1))).map(luma)
        let (low, high) = (row[0], row[47])
        return (row.max()! - high) / (high - low)
    }

    @Test func sharpeningOvershootsLikePeriodCompacts() throws {
        let full = try Self.overshoot(processing: 1)
        #expect(full >= 0.15 && full <= 0.21, "overshoot at processing 1: \(full)")
        let none = try Self.overshoot(processing: 0)
        #expect(none < 0.01, "no halos without processing: \(none)")
    }

    @Test func processingAddsPurpleFringeAroundClippedLight() throws {
        // A 1600 px frame (fringe sigma 1.5 px) cut from a square with a 32 px light at its centre.
        let scene = SceneFixtures.highlightPoint(size: 1600, radius: 8, level: 40).cropped(
            to: CGRect(x: 0, y: 200, width: 1600, height: 1200))
        func ring(_ processing: Double) throws -> SIMD3<Double> {
            let image = try Self.render(scene, Self.adjust { $0.halation = processing })
            // Just outside the light, on the row through its centre.
            return Self.codes(image.cropped(to: CGRect(x: 800 + 33, y: 600, width: 1, height: 1)))[0]
        }
        let (clean, fringed) = (try ring(0), try ring(1))
        #expect(fringed.z - clean.z > 5 && fringed.z - fringed.y > clean.z - clean.y, "clean \(clean), fringed \(fringed)")
    }

    // MARK: White balance

    /// Period compacts under tungsten (published lab tests): mid-gray R +9.5…11.6 %, B −9.9…−17 % in
    /// code values against a neutral render. The develop neutralises the light; the digicam process
    /// puts back what its auto white balance leaves.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func tungstenRAWKeepsAPeriodCast(_ mosaic: SyntheticDNG.Mosaic) throws {
        let chart = PatchChart(Array(repeating: SIMD3(repeating: 0.18), count: 12), cell: 48, columns: 4)
        let light = SyntheticDNG.planckianChromaticity(kelvin: 2850)
        let negative = try Self.renderer.developer.develop(RAWDevelopChart.dng(mosaic, chart: chart, light: light, taggedLight: light))
        let asShot = try #require(negative.asShotWhiteBalance)
        #expect(abs(asShot.temperature - 2850) < 20)
        let unknownLight = Negative(image: negative.image, contract: negative.contract)
        func centreCodes(_ n: Negative) throws -> SIMD3<Double> {
            let image = try Self.renderer.render(n, Self.clean)
            let (w, h) = (Int(image.extent.width), Int(image.extent.height))
            let pixels = Self.centre(Self.codes(image), width: w, height: h, size: 16)
            return pixels.reduce(.zero, +) / Double(pixels.count)
        }
        let ratio = try centreCodes(negative) / centreCodes(unknownLight)
        // A residual along the Planckian locus can't hold both: R lands in the measured range
        // (+9.6 %), B 2.5 points beyond it (−19.5 %).
        #expect(ratio.x >= 1.08 && ratio.x <= 1.12, "R \(ratio.x)")
        #expect(ratio.z >= 0.78 && ratio.z <= 0.83, "B \(ratio.z)")
    }

    @Test func shadeRendersSlightlyCoolAndDaylightIsTheReference() throws {
        let gray = Self.flat(0.18, width: 40, height: 30)
        func centre(_ asShot: Double?) throws -> SIMD3<Double> {
            Self.codes(try Self.render(gray, Self.clean, asShot: asShot))[15 * 40 + 20]
        }
        let (unknown, daylight, shade) = (try centre(nil), try centre(DigicamLook.whiteBalanceReference), try centre(7500))
        #expect(abs(unknown.x - daylight.x) < 0.01 && abs(unknown.z - daylight.z) < 0.01)
        #expect(shade.z > daylight.z && shade.x < daylight.x, "shade \(shade), daylight \(daylight)")
    }

    @Test func warmthAndTintShiftTheWhiteBalance() {
        let neutral = DigicamModel.whiteBalanceGains(asShotTemperature: nil, warmth: 0, tint: 0)
        let warm = DigicamModel.whiteBalanceGains(asShotTemperature: nil, warmth: 1, tint: 0)
        let magenta = DigicamModel.whiteBalanceGains(asShotTemperature: nil, warmth: 0, tint: 1)
        #expect(warm.x / warm.z > neutral.x / neutral.z)
        #expect(magenta.y < neutral.y)
        for g in [neutral, warm, magenta] { #expect(abs(DigicamModel.luma(g) - 1) < 1e-12) }
    }

    // MARK: Persistence

    @Test func recipesCarryTheProcessInTheEngineModel() throws {
        let look = try #require(CuratedLooks.recipes.first { $0.adjustments.process == .digicam })
        let json = String(decoding: try look.encoded(), as: UTF8.self)
        #expect(json.contains("\"engineModel\" : \"emulsion-digicam-v1\""))
        #expect(!json.contains("\"process\""), "the process travels as the engine model only")
        #expect(try Recipe.decode(look.encoded()) == look)
        var photo = Adjustments()
        photo.seed = 41
        #expect(look.applying(to: photo).process == .digicam)
        #expect(look.applying(to: photo).seed == 41)
    }

    /// A film recipe file written before processes existed: decodes the same and re-encodes byte for byte.
    @Test func filmRecipesAreUnchanged() throws {
        let saved = """
            {
              "adjustments" : {
                "color" : 0,
                "exposure" : 1.2,
                "grain" : 0.35,
                "halation" : 0.35,
                "highlights" : 0,
                "shadows" : 0,
                "tint" : -0.2,
                "warmth" : 0.4
              },
              "engineModel" : "emulsion-default-v1",
              "formatVersion" : 1,
              "id" : "8E2B3C64-6A0B-4B8D-9C64-4F1E0D2A9B11",
              "name" : "Evening",
              "summary" : ""
            }
            """
        let recipe = try Recipe.decode(Data(saved.utf8))
        #expect(recipe.adjustments.process == .film)
        #expect(String(decoding: try recipe.encoded(), as: UTF8.self) == saved)
        #expect(throws: EmulsionError.recipeModelUnsupported) {
            try Recipe.decode(Data(saved.replacingOccurrences(of: "emulsion-default-v1", with: "emulsion-future-v1").utf8))
        }
    }

    @Test func editsWithoutOrWithAnUnknownProcessRenderAsFilm() throws {
        #expect(try JSONDecoder().decode(Adjustments.self, from: Data(#"{"exposure": 1}"#.utf8)).process == .film)
        let future = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"exposure": 1, "process": "hologram"}"#.utf8))
        #expect(future.process == .film)
        #expect(future.exposure == 1, "the rest of the edit survives")
        let digicam = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"process": "digicam"}"#.utf8))
        #expect(digicam.process == .digicam)
        #expect(digicam.clamped().process == .digicam)
    }
}
