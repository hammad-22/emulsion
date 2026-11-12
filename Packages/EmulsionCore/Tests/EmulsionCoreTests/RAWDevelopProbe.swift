import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

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
        try #require(CIRAWFilter(imageData: data, identifierHint: Developer.dngTypeIdentifier))
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
        var nanCount: Int { pixels.filter { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }.count }
    }

    static func read(_ raw: CIRAWFilter) -> Readout? {
        let start = Date()
        guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else { return nil }
        return read(image, since: start)
    }

    static func read(_ image: CIImage, since start: Date = Date()) -> Readout {
        let pixels = Fixtures.linear(image)
        return Readout(extent: image.extent, pixels: pixels, milliseconds: Date().timeIntervalSince(start) * 1000)
    }

    static func means(_ out: Readout, chart: PatchChart) -> [SIMD3<Double>] {
        chart.means(of: out.pixels, width: Int(out.extent.width), height: Int(out.extent.height))
    }

    static func mean(_ pixels: [SIMD3<Double>]) -> SIMD3<Double> { pixels.reduce(.zero, +) / Double(pixels.count) }

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
                var decoders =
                    "  supportedDecoderVersions=\(raw.supportedDecoderVersions.map(\.rawValue)) default decoderVersion=\(raw.decoderVersion.rawValue)"
                if #available(macOS 27.0, iOS 27.0, *) {
                    let listed = raw.supportedDecoderVersions
                    decoders +=
                        " version9 listed=\(listed.contains(.version9)) version9DNG listed=\(listed.contains(.version9DNG))"
                        + " default is 9DNG=\(raw.decoderVersion == .version9DNG)"
                }
                print(decoders)
                print(
                    "  defaults: native \(raw.nativeSize) orientation \(raw.orientation.rawValue) baselineExposure \(raw.baselineExposure)"
                        + " exposure \(raw.exposure) shadowBias \(raw.shadowBias) boost \(raw.boostAmount)/\(raw.boostShadowAmount)"
                        + " gamutMap \(raw.isGamutMappingEnabled) HR \(raw.isHighlightRecoverySupported)/\(raw.isHighlightRecoveryEnabled)"
                        + " localToneMap \(raw.isLocalToneMapSupported)/\(raw.localToneMapAmount)"
                        + " contrast \(raw.isContrastSupported)/\(raw.contrastAmount) EDR \(raw.extendedDynamicRangeAmount)"
                        + " neutral \(raw.neutralTemperature) K tint \(raw.neutralTint) xy \(raw.neutralChromaticity)"
                        + " draft \(raw.isDraftModeEnabled) scale \(raw.scaleFactor) lensCorrection \(raw.isLensCorrectionSupported)"
                        + " NR lum \(raw.isLuminanceNoiseReductionSupported)/\(raw.luminanceNoiseReductionAmount)"
                        + " color \(raw.isColorNoiseReductionSupported)/\(raw.colorNoiseReductionAmount)"
                        + " sharpness \(raw.isSharpnessSupported)/\(raw.sharpnessAmount)")

                let midIndex = try #require(RAWDevelopChart.wedgeStops.firstIndex(of: 0))
                func midGray(_ configure: (CIRAWFilter) -> Void) throws -> SIMD3<Double> {
                    let raw = try Self.filter(data)
                    RAWDevelopSupport.applyPreMOV79Develop(raw)
                    configure(raw)
                    return Self.means(try #require(Self.read(raw)), chart: chart)[midIndex]
                }
                let defaultOutput = try midGray { _ in }
                let plusOne = try midGray { $0.baselineExposure += 1 }
                let zeroed = try midGray { $0.baselineExposure = 0 }
                let exposurePlusOne = try midGray { $0.exposure = 1 }
                print(
                    "  scene 0.18 patch (pre-MOV-79 settings): default \(defaultOutput.fourDigits); baselineExposure+1 \(plusOne.fourDigits)"
                        + " (G ratio \((plusOne.y / defaultOutput.y).fourDigits)); baselineExposure=0 \(zeroed.fourDigits);"
                        + " exposure=1 \(exposurePlusOne.fourDigits) (G ratio \((exposurePlusOne.y / defaultOutput.y).fourDigits))")
            }
        }
    }

    // MARK: 1. Wedge

    @Test func wedge() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let cameras = RAWDevelopChart.cameraValues(RAWDevelopChart.scene)
        let dump = ProcessInfo.processInfo.environment["EMULSION_RAW_PROBE_DUMP"]
        print("\n#### RAW probe: wedge (wide-gamut synthetic camera)")
        for (i, c) in cameras.enumerated() {
            print(
                "  patch \(i) scene linear sRGB \(RAWDevelopChart.scene[i].fourDigits) camera \(c.fourDigits)\(c.max() > 1 ? " CLIPS" : "")"
            )
        }
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in [0.0, 2.0] {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                if let dump {
                    try data.write(to: URL(fileURLWithPath: dump).appendingPathComponent("wedge-\(mosaic)-BE\(Int(stops)).dng"))
                }
                let scale = pow(2, stops)
                print("\n== wedge \(mosaic) BE=\(stops) shipped settings (Developer.develop)")
                Self.report(
                    Self.read(try RAWDevelopTests.developer.develop(data).image), chart: chart, cameras: cameras, scale: scale, rows: true)
                print("\n== wedge \(mosaic) BE=\(stops) pre-MOV-79 settings")
                let preMOV79 = try RAWDevelopSupport.preMOV79Negative(Self.filter(data))
                Self.report(Self.read(preMOV79.image), chart: chart, cameras: cameras, scale: scale, rows: true)

                for version in try Self.filter(data).supportedDecoderVersions {
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
                                if first { print("  first render of this decoder on this file: \(out.milliseconds.fourDigits) ms") }
                                first = false
                                Self.report(out, chart: chart, cameras: cameras, scale: scale, rows: false)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Probe labels only: a clipped patch within 2 % of neutral prints as "neutral", and a patch
    /// counts as still rising when it is over 1 % brighter than the one below it.
    static let neutralLabelLimit = 0.02
    static let risingRatio = 1.01

    /// SUMMARY lines for a developed wedge; `rows` adds a line per patch.
    static func report(_ out: Readout, chart: PatchChart, cameras: [SIMD3<Double>], scale: Double, rows: Bool) {
        let means = Self.means(out, chart: chart)
        print(
            "  extent=\(out.extent) render=\(out.milliseconds.fourDigits) ms max=\(RAWDevelopSupport.maxValue(out.pixels).fourDigits) NaN pixels=\(out.nanCount)"
        )
        if rows {
            print("  patch expected                          measured                        G ratio   R/G      B/G      sensor")
            for i in means.indices {
                let expected = chart.patches[i] * scale
                let m = means[i]
                print(
                    "  \(pad(String(i), 5)) \(pad(expected.fourDigits, 32)) \(pad(m.fourDigits, 31)) \(pad((m.y / expected.y).fourDigits, 9))"
                        + " \(pad((m.x / m.y).fourDigits, 8)) \(pad((m.z / m.y).fourDigits, 8)) \(cameras[i].max() > 1 ? "clipped" : "")"
                )
            }
        }
        let neutral = Array(RAWDevelopChart.neutralIndices)
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
            return (num / xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)).fourDigits
        }
        let below = unclipped.filter { chart.patches[$0].y * scale < 1 }
        let above = unclipped.filter { chart.patches[$0].y * scale >= 1 }
        let deviation = unclipped.map { abs(means[$0].y / (chart.patches[$0].y * scale) / midRatio - 1) }.max() ?? .nan
        let neutralError = unclipped.map { RAWDevelopSupport.neutralError(means[$0]) }.max() ?? .nan
        var lastRising = neutral.first ?? 0
        for i in neutral.dropFirst() where means[i].y > means[i - 1].y * risingRatio { lastRising = i }
        print(
            "  SUMMARY scale@0.18 (measured/expected G)=\(midRatio.fourDigits) log-log slope expected<1 \(slope(below)) [n=\(below.count)]"
                + " expected>=1 \(slope(above)) [n=\(above.count)] max |ratio/ratio@0.18-1| unclipped=\(deviation.fourDigits)")
        print(
            "  SUMMARY highest neutral G=\((neutral.map { means[$0].y }.max() ?? .nan).fourDigits) last patch still rising >1%: #\(lastRising)"
                + " (expected \((chart.patches[lastRising].y * scale).fourDigits)) neutral error unclipped max(|R/G-1|,|B/G-1|)=\(neutralError.fourDigits)"
        )
        for i in clipped {
            let m = means[i]
            let tint = RAWDevelopSupport.neutralError(m) < neutralLabelLimit ? "neutral" : "tinted"
            print(
                "  SUMMARY clipped #\(i) expected \((chart.patches[i].y * scale).fourDigits) measured \(m.fourDigits)"
                    + " R/G=\((m.x / m.y).fourDigits) B/G=\((m.z / m.y).fourDigits) \(tint)")
        }
        for i in RAWDevelopChart.outOfSRGBIndices {
            let expected = chart.patches[i] * scale
            print(
                "  SUMMARY out-of-sRGB #\(i) expected \(expected.fourDigits) measured \(means[i].fourDigits)"
                    + " min component expected \(expected.min().fourDigits) measured \(means[i].min().fourDigits)")
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
                    Self.report(try #require(Self.read(raw)), chart: chart, cameras: cameras, scale: pow(2, stops), rows: false)
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
        print("\n#### RAW probe: decoder versions x CIContext (pre-MOV-79 settings, EDR 0)")
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
                    let means = chart.means(
                        of: values.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }, width: Int(image.extent.width),
                        height: Int(image.extent.height))
                    let alpha = values.map(\.w)
                    func maxDifference(_ reference: [SIMD3<Double>]?) -> String {
                        guard let reference else { return "-" }
                        return (zip(means, reference).map { abs($0 - $1).max() / max(abs($1).max(), 1e-6) }.max() ?? .nan).fourDigits
                    }
                    print(
                        "  \(version.rawValue) | \(Self.pad(name, 44)) \(ms.fourDigits) ms alpha [\(alpha.min() ?? .nan), \(alpha.max() ?? .nan)]"
                            + " max rel. patch diff vs engine context, same decoder \(maxDifference(engine)); vs \(fresh.supportedDecoderVersions[0].rawValue) engine \(maxDifference(firstVersion))"
                    )
                    if engine == nil { engine = means }
                    if firstVersion == nil { firstVersion = means }
                }
            }
        }
    }

    // MARK: 2. White balance

    static let tungstenKelvin = 2856.0

    /// CIE 1931 xy of CIE daylight (D series) at correlated colour temperature `t`, CIE 15:2004
    /// eq. 3.3–3.4. Defined for 4000–25000 K only.
    static func daylightChromaticity(kelvin t: Double) -> SIMD2<Double>? {
        guard (4000...25000).contains(t) else { return nil }
        let t3 = t * t * t
        let x =
            t <= 7000
            ? -4.6070e9 / t3 + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
            : -2.0064e9 / t3 + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        return SIMD2(x, -3.000 * x * x + 2.870 * x - 0.275)
    }

    /// The gray patch's colour, ratios and OKLab distance (×100) from a neutral of equal luminance.
    static func grayLine(_ rgb: SIMD3<Double>) -> String {
        let neutral = SIMD3(repeating: RAWDevelopSupport.luminance(rgb))
        let dE = Fixtures.deltaE(Fixtures.toOKLab(rgb), Fixtures.toOKLab(neutral))
        return "gray \(pad(rgb.fourDigits, 32)) R/G \((rgb.x / rgb.y).fourDigits) B/G \((rgb.z / rgb.y).fourDigits)"
            + " max|.-1| \(RAWDevelopSupport.neutralError(rgb).fourDigits) dE(OKLab x100) \(dE.fourDigits)"
    }

    @Test func whiteBalance() throws {
        let scene = [SIMD3(repeating: RAWDevelopChart.midGray)] + RAWDevelopChart.chromaticScene.prefix(6)
        let chart = PatchChart(scene, cell: 64)
        let tungstenXY = SyntheticDNG.planckianChromaticity(kelvin: Self.tungstenKelvin)
        let temperatures = [2500.0, 3200, 4000, 5000, 6500, 8000, 10000]
        print(
            "\n#### RAW probe: white balance. Planckian \(Self.tungstenKelvin) K xy=\(tungstenXY) (Kim et al. 2002); D65 xy=\(SyntheticDNG.d65Chromaticity)"
        )
        for (cameraName, cm) in [("wide-gamut camera", RAWDevelopChart.camera), ("sRGB camera", SyntheticDNG.sRGBCameraFromXYZ)] {
            let d65Camera = SyntheticDNG.camera(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            let tungstenCamera = SyntheticDNG.camera(chromaticity: tungstenXY, cameraFromXYZ: cm)
            // Camera-space von Kries: exact for the gray patch, an approximation for chromatic ones.
            let lightRatio = tungstenCamera / d65Camera
            let underD65 = RAWDevelopChart.cameraValues(scene, cameraFromXYZ: cm)
            let underTungsten = underD65.map { $0 * lightRatio }
            let tungstenNeutral = SyntheticDNG.neutral(chromaticity: tungstenXY, cameraFromXYZ: cm)
            let d65Neutral = SyntheticDNG.neutral(chromaticity: SyntheticDNG.d65Chromaticity, cameraFromXYZ: cm)
            print("\n== \(cameraName): neutral(2856 K)=\(tungstenNeutral.fourDigits) neutral(D65)=\(d65Neutral.fourDigits)")
            for t in temperatures {
                let p = SyntheticDNG.planckianChromaticity(kelvin: t)
                let d = Self.daylightChromaticity(kelvin: t)
                print(
                    "  T=\(Int(t)) Planck xy=(\(p.x.fourDigits), \(p.y.fourDigits)) neutral \(SyntheticDNG.neutral(chromaticity: p, cameraFromXYZ: cm).fourDigits)"
                        + " daylight xy=\(d.map { "(\($0.x.fourDigits), \($0.y.fourDigits))" } ?? "undefined <4000 K")")
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

                func gray(_ data: Data, _ configure: (CIRAWFilter) -> Void = { _ in }) throws -> (rgb: SIMD3<Double>, raw: CIRAWFilter) {
                    let raw = try Self.filter(data)
                    RAWDevelopSupport.applyPreMOV79Develop(raw)
                    configure(raw)
                    return (Self.means(try #require(Self.read(raw)), chart: chart)[0], raw)
                }
                print("\n -- \(cameraName) \(mosaic)")
                for (name, data) in [
                    ("2856 K scene, correctly tagged", correct), ("2856 K scene, tagged D65", wrong), ("D65 scene, tagged D65", daylight),
                ] {
                    let raw = try Self.filter(data)
                    print(
                        "  \(Self.pad(name, 32)) as-shot temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) xy=\(raw.neutralChromaticity) | \(Self.grayLine(try gray(data).rgb))"
                    )
                }
                print("  wrongly tagged file:")
                let cases: [(String, (CIRAWFilter) -> Void)] = [
                    ("as shot", { _ in }),
                    (
                        "temp 2856 tint 0",
                        {
                            $0.neutralTemperature = Float(Self.tungstenKelvin)
                            $0.neutralTint = 0
                        }
                    ),
                    ("neutralChromaticity = Planck 2856 xy", { $0.neutralChromaticity = CGPoint(x: tungstenXY.x, y: tungstenXY.y) }),
                ]
                for (label, configure) in cases {
                    let (rgb, raw) = try gray(wrong, configure)
                    print(
                        "    \(Self.pad(label, 40)) read back temp=\(raw.neutralTemperature) tint=\(raw.neutralTint) | \(Self.grayLine(rgb))"
                    )
                }
                print("  temperature sweep, tint 0 (wrongly tagged file):")
                for t in temperatures.map(Float.init) {
                    let (rgb, raw) = try gray(wrong) {
                        $0.neutralTemperature = t
                        $0.neutralTint = 0
                    }
                    print("    T=\(Int(t)) read back \(raw.neutralTemperature)/\(raw.neutralTint) | \(Self.grayLine(rgb))")
                }
                let tints = try [Float(-50), 0, 50].map { tint in
                    let (rgb, raw) = try gray(wrong) {
                        $0.neutralTemperature = 6500
                        $0.neutralTint = tint
                    }
                    return "\(Int(tint)) (read \(raw.neutralTint)): R/G \((rgb.x / rgb.y).fourDigits) B/G \((rgb.z / rgb.y).fourDigits)"
                }
                print("  tint sweep at 6500 K: " + tints.joined(separator: "; "))
            }
        }
    }
}

// MARK: 3. Real ProRAW files

/// Real DNGs from a folder named by EMULSION_RAW_SAMPLES (never checked in). Skipped when unset.
extension RAWDevelopProbe {
    /// Files with the highest scaled-decode maximum that also get a full-size decode.
    static let fullSizeFileCount = 3

    /// The statistics `RAWDevelopRealFileTests` reports, plus the ones only the probe prints.
    struct DetailedStats {
        let frame: RAWDevelopSupport.FrameStats
        let max: SIMD3<Double>
        let min: Double
        let medianLuminance: Double
        let mean: SIMD3<Double>
        /// Mean R/G and B/G of the brightest 0.1 % of pixels by luminance: the colour of clipped highlights.
        let highlightRatios: SIMD2<Double>

        init(_ pixels: [SIMD3<Double>]) {
            let frame = RAWDevelopSupport.FrameStats(pixels)
            self.frame = frame
            max = pixels.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
            min = pixels.map { $0.min() }.min() ?? .nan
            let sortedLuminance = pixels.map(RAWDevelopSupport.luminance).sorted()
            medianLuminance = sortedLuminance[sortedLuminance.count / 2]
            mean = RAWDevelopProbe.mean(pixels)
            let brightest = pixels.filter { RAWDevelopSupport.luminance($0) >= frame.p999 }
            let brightMean = brightest.reduce(SIMD3<Double>.zero, +) / Double(Swift.max(brightest.count, 1))
            highlightRatios = SIMD2(brightMean.x / brightMean.y, brightMean.z / brightMean.y)
        }

        var line: String {
            "max \(max.fourDigits) p99.9 lum \(frame.p999.fourDigits) >1 \(frame.over1.fourDigits) >2 \(frame.over2.fourDigits)"
                + " >4 \(frame.over4.fourDigits) median lum \(medianLuminance.fourDigits) min \(min.fourDigits)"
                + " top-0.1% R/G \(highlightRatios.x.fourDigits) B/G \(highlightRatios.y.fourDigits)"
        }
    }

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
            raw.scaleFactor = Float(min(1, RAWDevelopSupport.previewLongEdge / max(raw.nativeSize.width, raw.nativeSize.height)))
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
        print(
            "\n#### RAW probe: real files (\(urls.count) DNGs), decoded at a \(Int(RAWDevelopSupport.previewLongEdge)) px long edge unless noted"
        )
        var asShot = [(name: String, temperature: Float)]()
        var scaledMaxima = [(url: URL, max: Double)]()
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
            var scaledMax = -Double.infinity
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
                            identity = " | vs EDR 0 on pixels <0.9: max abs diff \(diff.fourDigits) over \(below.count) px"
                        }
                        let stats = DetailedStats(out.pixels)
                        scaledMax = max(scaledMax, stats.frame.maxValue)
                        print("  EDR \(edr) GM \(gamut) HR \(hr) \(out.milliseconds.fourDigits) ms: \(stats.line)\(identity)")
                    }
                }
            }
            scaledMaxima.append((url, scaledMax))
            for version in raw.supportedDecoderVersions {
                let raw = try Self.realFilter(url)
                Self.apply(Settings(edr: 2, gamutMapping: false, highlightRecovery: true, decoder: version), raw)
                guard let out = Self.read(raw) else {
                    print("  decoder \(version.rawValue) EDR 2 GM off: no output")
                    continue
                }
                let stats = DetailedStats(out.pixels)
                print(
                    "  decoder \(version.rawValue) EDR 2 GM off HR on \(out.milliseconds.fourDigits) ms: max \(stats.max.fourDigits)"
                        + " median lum \(stats.medianLuminance.fourDigits) mean RGB \(stats.mean.fourDigits)")
            }
        }
        try realFullSize(scaledMaxima.sorted { $0.max > $1.max }.prefix(Self.fullSizeFileCount).map(\.url))
        try realWhiteBalance(urls, asShot: asShot)
    }

    func realFullSize(_ urls: [URL]) throws {
        print("\n#### RAW probe: full-size maxima of the \(urls.count) files with the highest scaled maximum")
        for url in urls {
            print("== \(url.deletingPathExtension().lastPathComponent)")
            for edr in [Float(0), 1, 2] {
                for gamut in [true, false] {
                    let raw = try Self.realFilter(url, scaled: false)
                    Self.apply(Settings(edr: edr, gamutMapping: gamut, highlightRecovery: true), raw)
                    let start = Date()
                    guard let image = raw.outputImage else { continue }
                    let max = Self.areaMaximum(image)
                    print(
                        "  FULL SIZE \(image.extent.size) EDR \(edr) GM \(gamut) HR on: max \(max.fourDigits) (\((Date().timeIntervalSince(start) * 1000).fourDigits) ms)"
                    )
                }
            }
        }
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
                print("== \(label) \(pick.name) as shot \(temperature) K tint \(tint): mean RGB \(Self.mean(asShotPixels).fourDigits)")
                for t in [Float(3200), 5000, 6500] {
                    let raw = try Self.realFilter(url)
                    raw.neutralTemperature = t
                    raw.neutralTint = tint
                    let mean = Self.mean(try #require(Self.read(raw)).pixels)
                    print(
                        "  T \(Int(t)) tint \(tint): mean RGB \(mean.fourDigits) R/G \((mean.x / mean.y).fourDigits) B/G \((mean.z / mean.y).fourDigits)"
                    )
                }
                let reset = try Self.realFilter(url)
                reset.neutralTemperature = temperature
                reset.neutralTint = tint
                let resetPixels = try #require(Self.read(reset)).pixels
                let diff = zip(asShotPixels, resetPixels).map { abs($0 - $1).max() }.max() ?? .nan
                print(
                    "  set temp/tint to as-shot values: max abs diff vs as shot \(diff.fourDigits) (read back \(reset.neutralTemperature)/\(reset.neutralTint))"
                )
            }
        }
    }
}
