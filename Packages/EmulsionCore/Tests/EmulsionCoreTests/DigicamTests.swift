import CoreImage
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionCore

struct DigicamTests {
    static var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

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

    static func render(_ scene: CIImage, _ a: Adjustments, asShot: Double? = nil, intent: RenderIntent = .preview) throws -> CIImage {
        let negative = Negative(
            image: scene, contract: .sceneReferred, asShotWhiteBalance: asShot.map { CameraWhiteBalance(temperature: $0, tint: 0) })
        return try renderer.render(negative, a, intent: intent)
    }

    static func codes(_ image: CIImage) -> [SIMD3<Double>] { Fixtures.encodedFloats(image, space: srgb).map { $0 * 255 } }

    static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }

    static let sensorWidth = 2592, sensorHeight = 1944
    /// Sourced: ISO 12232 mid-gray code; owner-directed black floor (docs/DIGICAM.md).
    static let middleGrayCode = 118.0, blackFloorCode = 22.0
    static let tungstenKelvin = 2850.0
    static let grayChart = PatchChart(Array(repeating: SIMD3(repeating: 0.18), count: 12), cell: 48, columns: 4)

    static func centre(_ pixels: [SIMD3<Double>], width: Int, height: Int, size: Int) -> [SIMD3<Double>] {
        let (x0, y0) = ((width - size) / 2, (height - size) / 2)
        return (y0..<y0 + size).flatMap { y in (x0..<x0 + size).map { pixels[y * width + $0] } }
    }

    static func centreCodes(_ negative: Negative) throws -> SIMD3<Double> {
        let image = try renderer.render(negative, clean)
        let pixels = centre(codes(image), width: Int(image.extent.width), height: Int(image.extent.height), size: 16)
        return pixels.reduce(.zero, +) / Double(pixels.count)
    }

    static let patches: [SIMD3<Double>] =
        SceneFixtures.chart24Patches.map { SIMD3<Double>($0.linear) }
        + stride(from: -8.0, through: 4.0, by: 0.5).map { SIMD3(repeating: 0.18 * pow(2, $0)) }
        + [SIMD3(3, 0.2, 0.05), SIMD3(0.4, 1.6, 0.2), SIMD3(0.3, 0.6, 2.4), SIMD3(-0.01, 0.05, 0.1), SIMD3(1.2, 1.0, 0.9)]
    static let block = 8, columns = 12, rows = 9

    /// Encoded 0…1 at block centres, GPU float against the Double mirror.
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
                for c in 0..<3 { worst = max(worst, abs(ColorMath.encodeSRGB(gpu[c]) - ColorMath.encodeSRGB(expected[c]))) }
            }
            #expect(worst <= Self.mirrorTolerance, "asShot \(asShot.map { "\($0)" } ?? "nil"): \(worst)")
        }
    }

    @Test func midGrayLandsOnItsCodeAndBlackOnTheFloor() throws {
        let encoded = { (x: Double) in ColorMath.encodeSRGB(DigicamModel.toneCurve(x)) * 255 }
        let x = (0.18 / DigicamLook.clip - DigicamLook.blackOffset) / (1 - DigicamLook.blackOffset)
        #expect(abs(encoded(x) - Self.middleGrayCode) < 1e-9)
        #expect(abs(encoded(1) - 255) < 1e-9, "the clip reaches white")
        #expect(abs(encoded(0) - Self.blackFloorCode) < 1e-9, "black is lifted to the floor")
        let scene = Fixtures.image(width: 40, height: 30, space: SceneFixtures.linear) { x, _ in SIMD3(repeating: x < 20 ? 0 : 0.18) }
        let pixels = Self.codes(try Self.render(scene, Self.clean))
        let (black, gray) = (pixels[15 * 40 + 10], pixels[15 * 40 + 30])
        #expect(abs(DigicamModel.luma(gray) - Self.middleGrayCode) < 1, "\(gray)")
        #expect(abs(DigicamModel.luma(black) - Self.blackFloorCode) < 0.5, "\(black)")
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

    @Test(arguments: [
        (4032, 3024, 2592, 1944), (4032, 2268, 2592, 1944), (3024, 4032, 1944, 2592), (8064, 6048, 2592, 1944),
        (1600, 1200, 1600, 1200), (1600, 900, 1200, 900), (900, 1600, 900, 1200), (2592, 1944, 2592, 1944),
    ])
    func outputIsTheSensorFrame(_ size: (Int, Int, Int, Int)) throws {
        let scene = SceneFixtures.flat(0.18, width: size.0, height: size.1)
        let rendered = try Self.render(scene, Self.adjust { ($0.grain, $0.halation) = (0.35, 0.5) })
        #expect(rendered.extent == CGRect(x: 0, y: 0, width: size.2, height: size.3))
        let moved = scene.transformed(by: CGAffineTransform(translationX: 37, y: -11))
        #expect(try Self.render(moved, Self.clean).extent == rendered.extent, "output at the origin")
    }

    @Test func cropIsCentredAndDownscaleDoesNotDarkenEdges() throws {
        let scene = Fixtures.image(width: 320, height: 180, space: SceneFixtures.linear) { x, _ in
            x < 40 || x >= 280 ? SIMD3(repeating: 1) : SIMD3(repeating: 0.18)
        }
        let image = try Self.render(scene, Self.clean)
        #expect(image.extent.size == CGSize(width: 240, height: 180))
        let pixels = Self.codes(image)
        #expect(pixels.allSatisfy { $0.y < 125 }, "no band left after the crop")
        let large = try Self.render(SceneFixtures.flat(0.18, width: 3200, height: 2400), Self.clean)
        let edge = Self.codes(large.cropped(to: CGRect(x: 0, y: 972, width: 2, height: 1)))
        #expect(abs(edge[0].y - edge[1].y) < 1, "\(edge)")
    }

    @Test func noiseIsDeterministicSeededAndZeroMean() throws {
        let scene = SceneFixtures.flat(0.09, width: 1200, height: 900)
        func lumas(_ seed: Double, grain: Double = 1) throws -> [Double] {
            let pixels = Self.codes(try Self.render(scene, Self.adjust { ($0.grain, $0.seed) = (grain, seed) }))
            return Self.centre(pixels, width: 1200, height: 900, size: 200).map(DigicamModel.luma)
        }
        let three = try lumas(3)
        #expect(try lumas(3) == three, "same seed, same noise")
        #expect(try lumas(4) != three, "different seed, different noise")
        let clean = try lumas(3, grain: 0)
        #expect(try lumas(9, grain: 0) == clean, "no noise at 0, whatever the seed")
        #expect(EmulsionTestCase.sd(clean) < EmulsionTestCase.sd(three) / 5, "only the vignette's gradient without noise")
        #expect(abs(Self.mean(three) - Self.mean(clean)) < 0.5, "zero-mean within half a code")
    }

    /// Measured 5.02 codes (owner direction, MOV-149); period JPEGs read about 2.
    static let defaultNoiseCodes = 5.0
    static let noiseTolerance = 0.5

    @Test func defaultNoiseIsFiveCodesTwoStopsUnderMidGray() throws {
        let a = Self.adjust { ($0.grain, $0.halation, $0.seed) = (DigicamLook.defaultNoise, DigicamLook.defaultProcessing, 5) }
        let (w, h) = (Self.sensorWidth, Self.sensorHeight)
        let image = try Self.render(SceneFixtures.flat(0.18 / 4, width: w, height: h), a, intent: .export)
        let pixels = Self.centre(Self.codes(image), width: w, height: h, size: 256)
        let sigma = EmulsionTestCase.sd(pixels.map(DigicamModel.luma))
        #expect(abs(sigma - Self.defaultNoiseCodes) <= Self.noiseTolerance, "luma σ \(sigma) codes")
    }

    /// Step-edge (0.045 → 0.36) overshoot as a fraction of the step, bright side.
    static func overshoot(processing: Double) throws -> Double {
        let (w, h) = (sensorWidth, sensorHeight)
        let scene = Fixtures.image(width: w, height: h, space: SceneFixtures.linear) { x, _ in
            SIMD3(repeating: x < w / 2 ? 0.045 : 0.36)
        }
        let image = try render(scene, adjust { $0.halation = processing })
        let row = codes(image.cropped(to: CGRect(x: w / 2 - 24, y: h / 2, width: 48, height: 1))).map(DigicamModel.luma)
        let (low, high) = (row[0], row[47])
        return (row.max()! - high) / (high - low)
    }

    /// Measured 30.3 % at processing 1 and 20.7 % at the default (owner direction, MOV-149).
    @Test func sharpeningOvershootsAboutThirtyPercentAtFullProcessing() throws {
        let full = try Self.overshoot(processing: 1)
        let standard = try Self.overshoot(processing: DigicamLook.defaultProcessing)
        #expect(full >= 0.27 && full <= 0.33, "overshoot at processing 1: \(full)")
        #expect(standard >= 0.18 && standard <= 0.24, "overshoot at the default: \(standard)")
        let none = try Self.overshoot(processing: 0)
        #expect(none < 0.01, "no halos without processing: \(none)")
    }

    @Test(arguments: [0, 0.2])
    func cornersAreNoSharperThanTheCentre(processing: Double) throws {
        let (w, h) = (Self.sensorWidth, Self.sensorHeight)
        let stripes = Fixtures.image(width: w, height: h, space: SceneFixtures.linear) { x, _ in
            SIMD3(repeating: x.isMultiple(of: 2) ? 0.09 : 0.36)
        }
        let image = try Self.render(stripes, Self.adjust { $0.halation = processing })
        func contrast(x: Int, y: Int) -> Double {
            let window = Self.codes(image.cropped(to: CGRect(x: x, y: y, width: 32, height: 32)))
            return EmulsionTestCase.sd(window.map(DigicamModel.luma))
        }
        let centre = contrast(x: w / 2 - 16, y: h / 2 - 16)
        let corner = contrast(x: 8, y: 8)
        #expect(corner <= centre + 0.01, "corner \(corner), centre \(centre) codes")
    }

    @Test func onlyExportsWithProcessingAreJPEGCompressed() throws {
        let scene = Fixtures.image(width: 640, height: 480, space: SceneFixtures.linear) { x, y in
            SIMD3(Float(x % 7) / 7, Float(y % 5) / 5, 0.2)
        }
        let a = Self.adjust { $0.halation = 1 }
        let preview = Self.codes(try Self.render(scene, a))
        let export = Self.codes(try Self.render(scene, a, intent: .export))
        let largest =
            zip(preview, export).map { (pair: (SIMD3<Double>, SIMD3<Double>)) in
                (pair.0 - pair.1).replacing(with: -(pair.0 - pair.1), where: pair.0 .< pair.1).max()
            }.max() ?? 0
        #expect(largest > 1, "the export carries JPEG compression: \(largest)")
        let clean = Self.adjust { $0.halation = 0 }
        #expect(Self.codes(try Self.render(scene, clean)) == Self.codes(try Self.render(scene, clean, intent: .export)))
    }

    @Test func processingAddsPurpleFringeAroundClippedLight() throws {
        let scene = SceneFixtures.highlightPoint(size: 1600, radius: 8, level: 40).cropped(
            to: CGRect(x: 0, y: 200, width: 1600, height: 1200))
        func violet(_ processing: Double) throws -> [Double] {
            let image = try Self.render(scene, Self.adjust { $0.halation = processing })
            return Self.codes(image.cropped(to: CGRect(x: 800 + 33, y: 600, width: 24, height: 1))).map { $0.z - $0.y }
        }
        let gain = zip(try violet(1), try violet(0)).map { $0 - $1 }.max() ?? 0
        #expect(gain > 5, "violet fringe, codes of blue over green: \(gain)")
    }

    /// Measured R +17.0 %, B −30.5 % at 2850 K (owner direction; docs/DIGICAM.md).
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func tungstenRAWKeepsAWarmCast(_ mosaic: SyntheticDNG.Mosaic) throws {
        let light = SyntheticDNG.planckianChromaticity(kelvin: Self.tungstenKelvin)
        let negative = try Self.renderer.developer.develop(
            RAWDevelopChart.dng(mosaic, chart: Self.grayChart, light: light, taggedLight: light))
        let asShot = try #require(negative.asShotWhiteBalance)
        #expect(abs(asShot.temperature - Self.tungstenKelvin) < 20)
        let unknownLight = Negative(image: negative.image, contract: negative.contract)
        let ratio = try Self.centreCodes(negative) / Self.centreCodes(unknownLight)
        #expect(ratio.x >= 1.15 && ratio.x <= 1.19, "R \(ratio.x)")
        #expect(ratio.z >= 0.67 && ratio.z <= 0.72, "B \(ratio.z)")
    }

    @Test func developWhiteBalanceKeepsTheAsShotLightsCast() throws {
        let light = SyntheticDNG.planckianChromaticity(kelvin: Self.tungstenKelvin)
        let data = RAWDevelopChart.dng(.linearRGB, chart: Self.grayChart, light: light, taggedLight: light)
        let developed = try Self.renderer.developer.develop(data, whiteBalance: CameraWhiteBalance(temperature: 4500, tint: 0))
        let asShot = try #require(developed.asShotWhiteBalance)
        #expect(abs(asShot.temperature - Self.tungstenKelvin) < 20, "the as-shot light, not the develop's")
        let withCast = try Self.centreCodes(developed)
        let withoutCast = try Self.centreCodes(Negative(image: developed.image, contract: developed.contract))
        #expect(withCast.x / withCast.z > 1.3 * withoutCast.x / withoutCast.z, "cast \(withCast), none \(withoutCast)")
    }

    @Test func shadeRendersSlightlyCoolAndDaylightIsTheReference() throws {
        let gray = SceneFixtures.flat(0.18, width: 40, height: 30)
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

    /// A format-1 film recipe reads as exactly these settings and re-encodes to the current format without loss.
    @Test func preProcessFilmRecipesReadAsFilm() throws {
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
        var expected = Adjustments()
        (expected.exposure, expected.warmth, expected.tint) = (1.2, 0.4, -0.2)
        (expected.grain, expected.halation, expected.color, expected.highlights, expected.shadows) = (0.35, 0.35, 0, 0, 0)
        (expected.process, expected.backing) = (.film, .remJet)
        (expected.grainSize, expected.grainColor) = (FilmLook.grainSize, FilmLook.grainColor)
        #expect(recipe.adjustments == expected)
        #expect(recipe.id == UUID(uuidString: "8E2B3C64-6A0B-4B8D-9C64-4F1E0D2A9B11") && recipe.name == "Evening")
        let rewritten = try recipe.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        #expect(object["formatVersion"] as? Int == Recipe.formatVersion && Recipe.formatVersion == 2)
        let reread = try Recipe.decode(rewritten)
        #expect(reread == recipe && reread.adjustments == expected)
        #expect(try Recipe.decode(reread.encoded()) == reread)
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
