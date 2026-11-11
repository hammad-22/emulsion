import CoreImage
import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing
import simd

/// Measures how Apple's CIRAWFilter develops synthetic DNGs (MOV-79): scale, clipping, EDR,
/// gamut mapping, highlight recovery, decoder versions and white balance. Prints tables and
/// asserts nothing about Apple's behaviour. Opt-in: EMULSION_RAW_PROBE=1; set
/// EMULSION_RAW_PROBE_DUMP=<dir> to also write the wedge DNGs there.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_RAW_PROBE"] != nil), .serialized)
struct RAWDevelopProbe {
    // MARK: Develop and measure

    struct Settings: CustomStringConvertible {
        var edr: Float = 0
        var gamutMapping = true
        var highlightRecovery: Bool?
        var decoder: CIRAWDecoderVersion?
        var description: String {
            "EDR=\(edr) gamutMap=\(gamutMapping) HR=\(highlightRecovery.map(String.init) ?? "n/a") decoder=\(decoder?.rawValue ?? "default")"
        }
    }

    static func filter(_ data: Data) throws -> CIRAWFilter {
        try #require(CIRAWFilter(imageData: data, identifierHint: "com.adobe.raw-image"))
    }

    static func apply(_ s: Settings, _ raw: CIRAWFilter) {
        RAWDevelopSupport.applyPreMOV79Develop(raw)
        if let decoder = s.decoder { raw.decoderVersion = decoder }
        raw.extendedDynamicRangeAmount = s.edr
        raw.isGamutMappingEnabled = s.gamutMapping
        if let hr = s.highlightRecovery, raw.isHighlightRecoverySupported { raw.isHighlightRecoveryEnabled = hr }
    }

    struct Readout {
        var extent: CGRect
        var pixels: [SIMD3<Double>]
        var milliseconds: Double
        var maxValue: Double { pixels.map { $0.max() }.max() ?? .nan }
        var nanCount: Int { pixels.filter { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }.count }
    }

    static func read(_ raw: CIRAWFilter) -> Readout? {
        let start = Date()
        guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else { return nil }
        let pixels = Fixtures.linear(image)
        return Readout(extent: image.extent, pixels: pixels, milliseconds: Date().timeIntervalSince(start) * 1000)
    }

    static func patchMeans(_ pixels: [SIMD3<Double>], extent: CGRect, chart: PatchChart) -> [SIMD3<Double>] {
        chart.means(of: pixels, width: Int(extent.width), height: Int(extent.height))
    }

    static func f(_ v: Double) -> String { String(format: "%.4g", v) }
    static func f(_ v: SIMD3<Double>) -> String { "(\(f(v.x)), \(f(v.y)), \(f(v.z)))" }
    static func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }

    /// Alpha and RGB through a chosen context, bottom row first.
    static func rgba(_ image: CIImage, context: CIContext) -> [SIMD4<Float>] {
        let w = Int(image.extent.width)
        let h = Int(image.extent.height)
        var values = [SIMD4<Float>](repeating: .zero, count: w * h)
        context.render(image, toBitmap: &values, rowBytes: w * 16, bounds: image.extent, format: .RGBAf, colorSpace: Fixtures.linearSRGB)
        return (0..<h).flatMap { row in values[((h - 1 - row) * w)..<((h - row) * w)] }
    }

    // MARK: 0. Defaults

    @Test func defaults() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        print("\n#### RAW probe: defaults (wedge chart \(chart.width)x\(chart.height), cell \(chart.cell))")
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in [0.0, 2.0] {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                let raw = try Self.filter(data)
                print("\n== \(mosaic) BaselineExposure tag=\(stops) bytes=\(data.count) Developer.isRAW=\(Developer.isRAW(data))")
                print("  nativeSize=\(raw.nativeSize) orientation=\(raw.orientation.rawValue)")
                print(
                    "  supportedDecoderVersions=\(raw.supportedDecoderVersions.map(\.rawValue)) default decoderVersion=\(raw.decoderVersion.rawValue)"
                )
                if #available(macOS 27.0, iOS 27.0, *) {
                    let listed = raw.supportedDecoderVersions
                    print(
                        "  version9 (\(CIRAWDecoderVersion.version9.rawValue)) listed=\(listed.contains(.version9))"
                            + " version9DNG (\(CIRAWDecoderVersion.version9DNG.rawValue)) listed=\(listed.contains(.version9DNG))"
                            + " default is 9DNG=\(raw.decoderVersion == .version9DNG)")
                }
                print(
                    "  baselineExposure=\(raw.baselineExposure) exposure=\(raw.exposure) shadowBias=\(raw.shadowBias)"
                        + " boostAmount=\(raw.boostAmount) boostShadowAmount=\(raw.boostShadowAmount)")
                print(
                    "  isGamutMappingEnabled=\(raw.isGamutMappingEnabled) isHighlightRecoverySupported=\(raw.isHighlightRecoverySupported)"
                        + " isHighlightRecoveryEnabled=\(raw.isHighlightRecoveryEnabled)")
                print(
                    "  isLocalToneMapSupported=\(raw.isLocalToneMapSupported) localToneMapAmount=\(raw.localToneMapAmount)"
                        + " isContrastSupported=\(raw.isContrastSupported) contrastAmount=\(raw.contrastAmount)"
                        + " extendedDynamicRangeAmount=\(raw.extendedDynamicRangeAmount)")
                print(
                    "  neutralTemperature=\(raw.neutralTemperature) neutralTint=\(raw.neutralTint)"
                        + " neutralChromaticity=\(raw.neutralChromaticity) isDraftModeEnabled=\(raw.isDraftModeEnabled) scaleFactor=\(raw.scaleFactor)"
                )
                print(
                    "  lensCorrection supported=\(raw.isLensCorrectionSupported) NR lum supported=\(raw.isLuminanceNoiseReductionSupported)"
                        + " (\(raw.luminanceNoiseReductionAmount)) color supported=\(raw.isColorNoiseReductionSupported) (\(raw.colorNoiseReductionAmount))"
                        + " sharpness supported=\(raw.isSharpnessSupported) (\(raw.sharpnessAmount))")

                let midIndex = try #require(RAWDevelopChart.wedgeStops.firstIndex(of: 0))
                func midGray(_ configure: (CIRAWFilter) -> Void) throws -> SIMD3<Double> {
                    let raw = try Self.filter(data)
                    RAWDevelopSupport.applyPreMOV79Develop(raw)
                    configure(raw)
                    let out = try #require(Self.read(raw))
                    return Self.patchMeans(out.pixels, extent: out.extent, chart: chart)[midIndex]
                }
                let defaultOutput = try midGray { _ in }
                let plusOne = try midGray { $0.baselineExposure += 1 }
                let zeroed = try midGray { $0.baselineExposure = 0 }
                let exposurePlusOne = try midGray { $0.exposure = 1 }
                print(
                    "  scene 0.18 patch (baseline settings): default \(Self.f(defaultOutput)); baselineExposure+1 \(Self.f(plusOne))"
                        + " (G ratio \(Self.f(plusOne.y / defaultOutput.y))); baselineExposure=0 \(Self.f(zeroed)); exposure=1 \(Self.f(exposurePlusOne))"
                        + " (G ratio \(Self.f(exposurePlusOne.y / defaultOutput.y)))")
            }
        }
    }

    // MARK: 1. Wedge

    @Test func wedge() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let cameras = RAWDevelopChart.cameraValues(RAWDevelopChart.scene)
        let neutralCount = RAWDevelopChart.wedgeStops.count
        let dump = ProcessInfo.processInfo.environment["EMULSION_RAW_PROBE_DUMP"]
        print("\n#### RAW probe: wedge (wide-gamut synthetic camera)")
        for (i, c) in cameras.enumerated() {
            print("  patch \(i) scene linear sRGB \(Self.f(RAWDevelopChart.scene[i])) camera \(Self.f(c))\(c.max() > 1 ? " CLIPS" : "")")
        }
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in [0.0, 2.0] {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                if let dump {
                    try data.write(to: URL(fileURLWithPath: dump).appendingPathComponent("wedge-\(mosaic)-BE\(Int(stops)).dng"))
                }
                let versions = try Self.filter(data).supportedDecoderVersions
                for version in versions {
                    var first = true
                    for edr in [Float(0), 1, 2] {
                        for gamut in [true, false] {
                            for hr in [true, false] {
                                let settings = Settings(edr: edr, gamutMapping: gamut, highlightRecovery: hr, decoder: version)
                                let raw = try Self.filter(data)
                                Self.apply(settings, raw)
                                print("\n== wedge \(mosaic) BE=\(stops) \(settings) (HR supported=\(raw.isHighlightRecoverySupported))")
                                guard let out = Self.read(raw) else {
                                    print("  outputImage nil or empty")
                                    continue
                                }
                                if first { print("  first render of this decoder on this file: \(Self.f(out.milliseconds)) ms") }
                                first = false
                                Self.report(
                                    out, chart: chart, cameras: cameras, neutralCount: neutralCount, scale: pow(2, stops))
                            }
                        }
                    }
                }
            }
        }
    }

    static func report(_ out: Readout, chart: PatchChart, cameras: [SIMD3<Double>], neutralCount: Int, scale: Double) {
        let means = patchMeans(out.pixels, extent: out.extent, chart: chart)
        print("  extent=\(out.extent) render=\(f(out.milliseconds)) ms max=\(f(out.maxValue)) NaN pixels=\(out.nanCount)")
        print("  patch expected                          measured                        G ratio   R/G      B/G      sensor")
        for i in means.indices {
            let expected = chart.patches[i] * scale
            let m = means[i]
            print(
                "  \(pad(String(i), 5)) \(pad(f(expected), 32)) \(pad(f(m), 31)) \(pad(f(m.y / expected.y), 9)) \(pad(f(m.x / m.y), 8)) \(pad(f(m.z / m.y), 8)) \(cameras[i].max() > 1 ? "clipped" : "")"
            )
        }
        let neutral = Array(0..<neutralCount)
        let unclipped = neutral.filter { cameras[$0].max() < 1 && means[$0].y > 1e-4 }
        let clipped = neutral.filter { cameras[$0].max() >= 1 }
        let midIndex = RAWDevelopChart.wedgeStops.firstIndex(of: 0) ?? 0
        let midRatio = means[midIndex].y / (chart.patches[midIndex].y * scale)
        func slope(_ indices: [Int]) -> String {
            guard indices.count >= 2 else { return "n/a" }
            let xs = indices.map { log2(chart.patches[$0].y * scale) }
            let ys = indices.map { log2(means[$0].y) }
            let mx = xs.reduce(0, +) / Double(xs.count)
            let my = ys.reduce(0, +) / Double(ys.count)
            let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
            return f(num / xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +))
        }
        let below = unclipped.filter { chart.patches[$0].y * scale < 1 }
        let above = unclipped.filter { chart.patches[$0].y * scale >= 1 }
        let deviation = unclipped.map { abs(means[$0].y / (chart.patches[$0].y * scale) / midRatio - 1) }.max() ?? .nan
        let neutralError = unclipped.map { max(abs(means[$0].x / means[$0].y - 1), abs(means[$0].z / means[$0].y - 1)) }.max() ?? .nan
        var lastRising = neutral.first ?? 0
        for i in neutral.dropFirst() where means[i].y > means[i - 1].y * 1.01 { lastRising = i }
        print(
            "  SUMMARY scale@0.18 (measured/expected G)=\(f(midRatio)) log-log slope expected<1 \(slope(below)) [n=\(below.count)]"
                + " expected>=1 \(slope(above)) [n=\(above.count)] max |ratio/ratio@0.18-1| unclipped=\(f(deviation))")
        print(
            "  SUMMARY highest neutral G=\(f(neutral.map { means[$0].y }.max() ?? .nan)) last patch still rising >1%: #\(lastRising)"
                + " (expected \(f(chart.patches[lastRising].y * scale))) neutral error unclipped max(|R/G-1|,|B/G-1|)=\(f(neutralError))")
        for i in clipped {
            let m = means[i]
            let tint = max(abs(m.x / m.y - 1), abs(m.z / m.y - 1)) < 0.02 ? "neutral" : "tinted"
            print(
                "  SUMMARY clipped #\(i) expected \(f(chart.patches[i].y * scale)) measured \(f(m)) R/G=\(f(m.x / m.y)) B/G=\(f(m.z / m.y)) \(tint)"
            )
        }
        for i in (chart.patches.count - RAWDevelopChart.outOfSRGBP3.count)..<chart.patches.count {
            print(
                "  SUMMARY out-of-sRGB #\(i) expected \(f(chart.patches[i] * scale)) measured \(f(means[i])) min component expected \(f((chart.patches[i] * scale).min())) measured \(f(means[i].min()))"
            )
        }
    }

    // MARK: 1a. Shadow bias

    @Test func shadowBias() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let cameras = RAWDevelopChart.cameraValues(RAWDevelopChart.scene)
        print("\n#### RAW probe: shadowBias (EDR 2, gamut mapping off, highlight recovery on, default decoder)")
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in [0.0, 2.0] {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                for bias: Float? in [nil, 0] {
                    let raw = try Self.filter(data)
                    Self.apply(Settings(edr: 2, gamutMapping: false, highlightRecovery: true), raw)
                    let defaultBias = raw.shadowBias
                    if let bias { raw.shadowBias = bias }
                    print("\n== shadowBias \(mosaic) BE=\(stops) shadowBias=\(raw.shadowBias) (default \(defaultBias))")
                    let out = try #require(Self.read(raw))
                    Self.report(out, chart: chart, cameras: cameras, neutralCount: RAWDevelopChart.wedgeStops.count, scale: pow(2, stops))
                }
            }
        }
    }

    // MARK: 1b. Decoders and working colour space

    /// FB24419261 (cited by Apple DTS): a tint with the 9.dng decoder under a custom working space.
    @Test func decoderAndContexts() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let contexts: [(String, CIContext)] = [
            (
                "engine (working extendedLinearSRGB, RGBAh)",
                CIContext(options: [.workingColorSpace: Fixtures.linearSRGB, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
            ),
            ("default CIContext()", CIContext()),
            (
                "working extendedLinearDisplayP3, RGBAf",
                CIContext(options: [.workingColorSpace: SceneFixtures.linearP3, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false])
            ),
        ]
        let shown =
            [RAWDevelopChart.wedgeStops.firstIndex(of: 0) ?? 0, RAWDevelopChart.wedgeStops.firstIndex(of: 2) ?? 0]
            + Array(RAWDevelopChart.wedgeStops.count..<RAWDevelopChart.scene.count)
        print("\n#### RAW probe: decoder versions x CIContext (baseline settings, EDR 0)")
        for mosaic in SyntheticDNG.Mosaic.allCases {
            let data = RAWDevelopChart.dng(mosaic, chart: chart)
            let fresh = try Self.filter(data)
            print(
                "\n== \(mosaic) default decoderVersion on a new filter: \(fresh.decoderVersion.rawValue) of \(fresh.supportedDecoderVersions.map(\.rawValue))"
            )
            var firstVersion: [SIMD3<Double>]?
            for version in fresh.supportedDecoderVersions {
                var engine: [SIMD3<Double>]?
                for (name, context) in contexts {
                    let raw = try Self.filter(data)
                    Self.apply(Settings(decoder: version), raw)
                    let start = Date()
                    guard let image = raw.outputImage, !image.extent.isInfinite, !image.extent.isEmpty else {
                        print("  \(version.rawValue) \(name): outputImage nil")
                        continue
                    }
                    let values = Self.rgba(image, context: context)
                    let ms = Date().timeIntervalSince(start) * 1000
                    let means = Self.patchMeans(
                        values.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }, extent: image.extent, chart: chart)
                    let alpha = values.map(\.w)
                    func maxDifference(_ reference: [SIMD3<Double>]?) -> String {
                        guard let reference else { return "-" }
                        return Self.f(zip(means, reference).map { abs($0 - $1).max() / max(abs($1).max(), 1e-6) }.max() ?? .nan)
                    }
                    print(
                        "  \(version.rawValue) | \(Self.pad(name, 44)) \(Self.f(ms)) ms alpha [\(alpha.min() ?? .nan), \(alpha.max() ?? .nan)]"
                            + " max rel. patch diff vs engine context, same decoder \(maxDifference(engine)); vs \(fresh.supportedDecoderVersions[0].rawValue) engine \(maxDifference(firstVersion))"
                    )
                    if engine == nil { engine = means }
                    if firstVersion == nil { firstVersion = means }
                    for i in shown {
                        let m = means[i]
                        print("      #\(i) \(Self.pad(Self.f(m), 32)) R/G \(Self.f(m.x / m.y)) B/G \(Self.f(m.z / m.y))")
                    }
                }
            }
        }
    }

    // MARK: 2. White balance

    static let tungstenKelvin = 2856.0

    struct GrayReport {
        var rgb: SIMD3<Double>
        var line: String {
            let y = 0.2126729 * rgb.x + 0.7151522 * rgb.y + 0.0721750 * rgb.z
            let error = max(abs(rgb.x / rgb.y - 1), abs(rgb.z / rgb.y - 1))
            let dE = Fixtures.deltaE(Fixtures.toOKLab(rgb), Fixtures.toOKLab(SIMD3(repeating: y)))
            return
                "gray \(RAWDevelopProbe.pad(RAWDevelopProbe.f(rgb), 32)) R/G \(RAWDevelopProbe.f(rgb.x / rgb.y)) B/G \(RAWDevelopProbe.f(rgb.z / rgb.y)) max|.-1| \(RAWDevelopProbe.f(error)) dE(OKLab x100) \(RAWDevelopProbe.f(dE))"
        }
    }

    @Test func whiteBalance() throws {
        let scene = [SIMD3(repeating: RAWDevelopChart.midGray)] + RAWDevelopChart.chromaticScene.prefix(6)
        let chart = PatchChart(scene, cell: 64)
        let tungstenXY = SyntheticDNG.planckianChromaticity(kelvin: Self.tungstenKelvin)
        print(
            "\n#### RAW probe: white balance. Planckian \(Self.tungstenKelvin) K xy=\(tungstenXY) (Kim et al. 2002); D65 xy=\(SyntheticDNG.d65Chromaticity)"
        )
        for (cameraName, cm) in [("wide-gamut camera", RAWDevelopChart.camera), ("sRGB camera", SyntheticDNG.cameraFromXYZ())] {
            let d65Camera = SyntheticDNG.camera(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            let tungstenCamera = SyntheticDNG.camera(chromaticity: tungstenXY, cameraFromXYZ: cm)
            // Camera-space von Kries: exact for the gray patch, an approximation for chromatic ones.
            let lightRatio = tungstenCamera / d65Camera
            let underTungsten = RAWDevelopChart.cameraValues(scene, cameraFromXYZ: cm).map { $0 * lightRatio }
            let underD65 = RAWDevelopChart.cameraValues(scene, cameraFromXYZ: cm)
            let tungstenNeutral = SyntheticDNG.neutral(chromaticity: tungstenXY, cameraFromXYZ: cm)
            let d65Neutral = SyntheticDNG.neutral(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            print("\n== \(cameraName): neutral(2856 K)=\(Self.f(tungstenNeutral)) neutral(D65)=\(Self.f(d65Neutral))")
            for t in [2500.0, 3200, 4000, 5000, 6500, 8000, 10000] {
                let p = SyntheticDNG.planckianChromaticity(kelvin: t)
                let d = SyntheticDNG.daylightChromaticity(kelvin: t)
                print(
                    "  T=\(Int(t)) Planck xy=(\(Self.f(p.x)), \(Self.f(p.y))) neutral \(Self.f(SyntheticDNG.neutral(chromaticity: p, cameraFromXYZ: cm)))"
                        + " daylight xy=\(d.map { "(\(Self.f($0.x)), \(Self.f($0.y)))" } ?? "undefined <4000 K")")
            }
            for mosaic in SyntheticDNG.Mosaic.allCases {
                func file(_ cameras: [SIMD3<Double>], neutral: SIMD3<Double>) -> Data {
                    let sensor = PatchChart(cameras, cell: chart.cell, columns: chart.columns)
                    return SyntheticDNG(mosaic: mosaic, width: chart.width, height: chart.height, asShotNeutral: neutral, cameraFromXYZ: cm)
                        .data { sensor.value(x: $0, y: $1) }
                }
                let correct = file(underTungsten, neutral: tungstenNeutral)
                let wrong = file(underTungsten, neutral: d65Neutral)
                let daylight = file(underD65, neutral: d65Neutral)

                func gray(_ data: Data, draft: Bool = false, _ configure: (CIRAWFilter) -> Void = { _ in }) throws -> (
                    GrayReport, CIRAWFilter
                ) {
                    let raw = try Self.filter(data)
                    RAWDevelopSupport.applyPreMOV79Develop(raw)
                    if draft {
                        raw.isDraftModeEnabled = true
                        raw.scaleFactor = 0.25
                    }
                    configure(raw)
                    let out = try #require(Self.read(raw))
                    return (GrayReport(rgb: Self.patchMeans(out.pixels, extent: out.extent, chart: chart)[0]), raw)
                }
                print("\n -- \(cameraName) \(mosaic)")
                var reported = (temperature: Float(0), tint: Float(0))
                for (name, data) in [
                    ("2856 K scene, correctly tagged", correct), ("2856 K scene, tagged D65", wrong), ("D65 scene, tagged D65", daylight),
                ] {
                    let raw = try Self.filter(data)
                    if name.hasPrefix("2856 K scene, correctly") { reported = (raw.neutralTemperature, raw.neutralTint) }
                    print(
                        "  \(Self.pad(name, 32)) as-shot temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) xy=\(raw.neutralChromaticity) | \(try gray(data).0.line)"
                    )
                }
                for draft in [false, true] {
                    print("  [\(draft ? "draft, scaleFactor 0.25" : "full size")] wrongly tagged file:")
                    let cases: [(String, (CIRAWFilter) -> Void)] = [
                        ("as shot", { _ in }),
                        (
                            "temp 2856 tint 0",
                            {
                                $0.neutralTemperature = Float(Self.tungstenKelvin)
                                $0.neutralTint = 0
                            }
                        ),
                        (
                            "temp/tint as read from correct file (\(reported.temperature), \(reported.tint))",
                            {
                                $0.neutralTemperature = reported.temperature
                                $0.neutralTint = reported.tint
                            }
                        ),
                        ("neutralChromaticity = Planck 2856 xy", { $0.neutralChromaticity = CGPoint(x: tungstenXY.x, y: tungstenXY.y) }),
                    ]
                    for (label, configure) in cases {
                        let (report, raw) = try gray(wrong, draft: draft, configure)
                        print(
                            "    \(Self.pad(label, 52)) read back temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) | \(report.line)")
                    }
                }
                print("  temperature sweep, tint 0 (wrongly tagged file):")
                for t in [Float(2500), 3200, 4000, 5000, 6500, 8000, 10000] {
                    let (report, raw) = try gray(wrong) {
                        $0.neutralTemperature = t
                        $0.neutralTint = 0
                    }
                    print("    T=\(Int(t)) read back \(raw.neutralTemperature)/\(raw.neutralTint) | \(report.line)")
                }
                print("  tint sweep at 6500 K:")
                for tint in [Float(-50), 0, 50] {
                    let (report, raw) = try gray(wrong) {
                        $0.neutralTemperature = 6500
                        $0.neutralTint = tint
                    }
                    print("    tint=\(Int(tint)) read back \(raw.neutralTemperature)/\(raw.neutralTint) | \(report.line)")
                }
                let raw = try Self.filter(wrong)
                let asShotTint = raw.neutralTint
                raw.neutralTint = 20
                raw.neutralTemperature = 4000
                print(
                    "  order: as-shot tint \(asShotTint); set tint 20 then temp 4000 -> read temp \(raw.neutralTemperature) tint \(raw.neutralTint)"
                )
                let tempFirst = try gray(wrong) {
                    $0.neutralTemperature = 4000
                    $0.neutralTint = 20
                }
                let tintFirst = try gray(wrong) {
                    $0.neutralTint = 20
                    $0.neutralTemperature = 4000
                }
                print("    temp then tint: read \(tempFirst.1.neutralTemperature)/\(tempFirst.1.neutralTint) | \(tempFirst.0.line)")
                print("    tint then temp: read \(tintFirst.1.neutralTemperature)/\(tintFirst.1.neutralTint) | \(tintFirst.0.line)")
            }
        }
    }
}

// MARK: 3. Real ProRAW files

/// Real DNGs from a folder named by EMULSION_RAW_SAMPLES (never checked in). Skipped when unset.
extension RAWDevelopProbe {
    /// Long edge of the scaled decode, to keep 48 MP files fast.
    static let previewLongEdge = 1024.0
    static let brightFiles = ["Divers_20240519-164224", "Divers_20240517-191806", "Divers_20240518-134907"]

    /// BitsPerSample, PhotometricInterpretation, Compression and SamplesPerPixel of the full-size
    /// raw IFD (NewSubFileType 0), read from the TIFF structure (IFD chain and SubIFDs).
    static func rawLayout(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let little = data.prefix(2) == Data("II".utf8)
        func read(_ offset: Int, _ size: Int) -> Int {
            guard offset >= 0, offset + size <= data.count else { return 0 }
            let bytes = data[data.startIndex + offset..<data.startIndex + offset + size]
            return (little ? bytes.reversed() : Array(bytes)).reduce(0) { $0 << 8 | Int($1) }
        }
        let typeSizes = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 8: 2, 9: 4, 10: 8, 13: 4]
        var queue = [read(4, 4)]
        var visited = Set<Int>()
        while let offset = queue.popLast() {
            guard offset > 0, visited.insert(offset).inserted else { continue }
            var tags = [Int: [Int]]()
            let count = read(offset, 2)
            for index in 0..<count {
                let entry = offset + 2 + index * 12
                let (tag, type, n) = (read(entry, 2), read(entry + 2, 2), read(entry + 4, 4))
                let size = typeSizes[type] ?? 1
                let base = size * n <= 4 ? entry + 8 : read(entry + 8, 4)
                tags[tag] = (0..<min(n, 8)).map { read(base + $0 * size, min(size, 4)) }
            }
            queue += tags[330] ?? []
            queue.append(read(offset + 2 + count * 12, 4))
            if tags[254]?.first ?? 0 == 0, let photometric = tags[262]?.first, [32803, 34892].contains(photometric) {
                return "raw IFD: BitsPerSample \(tags[258] ?? []) Photometric \(photometric) Compression \(tags[259] ?? [])"
                    + " SamplesPerPixel \(tags[277] ?? [1]) size \(tags[256] ?? [])x\(tags[257] ?? []) WhiteLevel \(tags[50717] ?? [])"
                    + " LinearizationTable \(tags[50712] == nil ? "no" : "yes")"
            }
        }
        return "raw IFD not found"
    }

    static func realFilter(_ url: URL, scaled: Bool = true) throws -> CIRAWFilter {
        let raw = try #require(CIRAWFilter(imageURL: url))
        RAWDevelopSupport.applyPreMOV79Develop(raw)
        if scaled {
            raw.scaleFactor = Float(min(1, previewLongEdge / max(raw.nativeSize.width, raw.nativeSize.height)))
        }
        return raw
    }

    /// Per-channel maximum computed on the GPU, for full-size frames too large to read back.
    static func areaMaximum(_ image: CIImage) -> SIMD3<Double> {
        let max = image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: Fixtures.linearSRGB, .workingFormat: CIFormat.RGBAf])
        context.render(
            max, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
            colorSpace: Fixtures.linearSRGB)
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    @Test(.enabled(if: RAWDevelopSupport.samplesFolders != nil)) func realFiles() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        print("\n#### RAW probe: real files (\(urls.count) DNGs), decoded at a \(Int(Self.previewLongEdge)) px long edge unless noted")
        var asShot = [(name: String, temperature: Float)]()
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            let raw = try Self.realFilter(url)
            asShot.append((name, raw.neutralTemperature))
            print(
                "\n== \(name) native \(raw.nativeSize) baselineExposure \(raw.baselineExposure) as-shot temp \(raw.neutralTemperature) tint \(raw.neutralTint)"
                    + " xy \(raw.neutralChromaticity) decoder \(raw.decoderVersion.rawValue) of \(raw.supportedDecoderVersions.map(\.rawValue))"
                    + " localToneMap supported \(raw.isLocalToneMapSupported) default \(raw.localToneMapAmount)"
                    + " HR supported \(raw.isHighlightRecoverySupported) shadowBias \(raw.shadowBias) scaleFactor \(raw.scaleFactor)")
            print("  \(try Self.rawLayout(url))")
            var edrZero = [String: [SIMD3<Double>]]()
            for gamut in [true, false] {
                for hr in [true, false] {
                    for edr in [Float(0), 1, 2] {
                        let raw = try Self.realFilter(url)
                        Self.apply(Settings(edr: edr, gamutMapping: gamut, highlightRecovery: hr), raw)
                        guard let out = Self.read(raw) else {
                            print("  EDR \(edr) GM \(gamut) HR \(hr): no output")
                            continue
                        }
                        let key = "\(gamut)-\(hr)"
                        var identity = ""
                        if edr == 0 {
                            edrZero[key] = out.pixels
                        } else if let base = edrZero[key], base.count == out.pixels.count {
                            let below = zip(base, out.pixels).filter { $0.0.max() < 0.9 }
                            let diff = below.map { abs($0.0 - $0.1).max() }.max() ?? .nan
                            identity = " | vs EDR 0 on pixels <0.9: max abs diff \(Self.f(diff)) over \(below.count) px"
                        }
                        print(
                            "  EDR \(edr) GM \(gamut) HR \(hr) \(Self.f(out.milliseconds)) ms: \(RAWDevelopSupport.FrameStats(out.pixels).line)\(identity)"
                        )
                    }
                }
            }
            for version in raw.supportedDecoderVersions {
                let raw = try Self.realFilter(url)
                Self.apply(Settings(edr: 2, gamutMapping: false, highlightRecovery: true, decoder: version), raw)
                guard let out = Self.read(raw) else {
                    print("  decoder \(version.rawValue) EDR 2 GM off: no output")
                    continue
                }
                let stats = RAWDevelopSupport.FrameStats(out.pixels)
                print(
                    "  decoder \(version.rawValue) EDR 2 GM off HR on \(Self.f(out.milliseconds)) ms: max \(Self.f(stats.max)) median lum \(Self.f(stats.median)) mean RGB \(Self.f(stats.mean))"
                )
            }
            if Self.brightFiles.contains(name) {
                for edr in [Float(0), 1, 2] {
                    for gamut in [true, false] {
                        let raw = try Self.realFilter(url, scaled: false)
                        Self.apply(Settings(edr: edr, gamutMapping: gamut, highlightRecovery: true), raw)
                        let start = Date()
                        guard let image = raw.outputImage else { continue }
                        let max = Self.areaMaximum(image)
                        print(
                            "  FULL SIZE \(image.extent.size) EDR \(edr) GM \(gamut) HR on: max \(Self.f(max)) (\(Self.f(Date().timeIntervalSince(start) * 1000)) ms)"
                        )
                    }
                }
            }
        }
        try realWhiteBalance(urls, asShot: asShot)
    }

    /// Two lowest as-shot temperatures (tungsten interiors) and the two closest to 5500 K (daylight).
    func realWhiteBalance(_ urls: [URL], asShot: [(name: String, temperature: Float)]) throws {
        let tungsten = asShot.sorted { $0.temperature < $1.temperature }.prefix(2)
        let daylight = asShot.sorted { abs($0.temperature - 5500) < abs($1.temperature - 5500) }.prefix(2)
        print("\n#### RAW probe: real-file white balance (EDR 0, gamut mapping on, default decoder)")
        for (label, picks) in [("tungsten", tungsten), ("daylight", daylight)] {
            for pick in picks {
                let url = try #require(urls.first { $0.deletingPathExtension().lastPathComponent == pick.name })
                let shot = try Self.realFilter(url)
                let (temperature, tint) = (shot.neutralTemperature, shot.neutralTint)
                let asShotPixels = try #require(Self.read(shot)).pixels
                print(
                    "== \(label) \(pick.name) as shot \(temperature) K tint \(tint): mean RGB \(Self.f(RAWDevelopSupport.FrameStats(asShotPixels).mean))"
                )
                for t in [Float(3200), 5000, 6500] {
                    let raw = try Self.realFilter(url)
                    raw.neutralTemperature = t
                    raw.neutralTint = tint
                    let mean = RAWDevelopSupport.FrameStats(try #require(Self.read(raw)).pixels).mean
                    print(
                        "  T \(Int(t)) tint \(tint): mean RGB \(Self.f(mean)) R/G \(Self.f(mean.x / mean.y)) B/G \(Self.f(mean.z / mean.y))"
                    )
                }
                let reset = try Self.realFilter(url)
                reset.neutralTemperature = temperature
                reset.neutralTint = tint
                let resetPixels = try #require(Self.read(reset)).pixels
                let diff = zip(asShotPixels, resetPixels).map { abs($0 - $1).max() }.max() ?? .nan
                print(
                    "  set temp/tint to as-shot values: max abs diff vs as shot \(Self.f(diff)) (read back \(reset.neutralTemperature)/\(reset.neutralTint))"
                )
            }
        }
    }
}

extension RAWDevelopSupport.FrameStats {
    var line: String {
        let f: (Double) -> String = RAWDevelopProbe.f
        let v: (SIMD3<Double>) -> String = RAWDevelopProbe.f
        return
            "max \(v(max)) p99.9 lum \(f(p999)) >1 \(f(over1)) >2 \(f(over2)) >4 \(f(over4)) median lum \(f(median)) min \(f(min)) top-0.1% R/G \(f(highlightRatios.x)) B/G \(f(highlightRatios.y))"
    }
}
