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
@Suite(.enabled(if: TestEnvironment.rawProbe.isSet), .serialized)
struct RAWDevelopProbe {
    /// BaselineExposure tags every synthetic file is probed at.
    static let baselineStopsSweep = [0.0, 2.0]
    static let edrAmounts: [Float] = [0, 1, 2]

    struct Settings: CustomStringConvertible {
        var edr: Float = 0
        var gamutMapping = true
        var highlightRecovery: Bool?
        var decoder: CIRAWDecoderVersion?
        var description: String {
            "EDR=\(edr) gamutMap=\(gamutMapping) HR=\(highlightRecovery.map(String.init) ?? "n/a") decoder=\(decoder?.rawValue ?? "default")"
        }
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
        var nanCount: Int { pixels.count(where: { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }) }
    }

    static func read(_ raw: CIRAWFilter) -> Readout? {
        let start = ContinuousClock.now
        guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else { return nil }
        return read(image, since: start)
    }

    static func read(_ image: CIImage, since start: ContinuousClock.Instant = .now) -> Readout {
        let pixels = Fixtures.linear(image)
        return Readout(extent: image.extent, pixels: pixels, milliseconds: start.duration(to: .now).milliseconds)
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

    @Test func defaults() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        print("\n#### RAW probe: defaults (wedge chart \(chart.width)x\(chart.height), cell \(chart.cell))")
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in Self.baselineStopsSweep {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                let raw = try RAWDevelopSupport.filter(data)
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
                    let raw = try RAWDevelopSupport.filter(data)
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

    @Test func wedge() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let cameras = RAWDevelopChart.cameraValues(RAWDevelopChart.scene)
        let dump = TestEnvironment.rawProbeDump.value
        print("\n#### RAW probe: wedge (wide-gamut synthetic camera)")
        for (i, c) in cameras.enumerated() {
            print(
                "  patch \(i) scene linear sRGB \(RAWDevelopChart.scene[i].fourDigits) camera \(c.fourDigits)\(c.max() > 1 ? " CLIPS" : "")"
            )
        }
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in Self.baselineStopsSweep {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                if let dump {
                    try data.write(to: URL(fileURLWithPath: dump).appendingPathComponent("wedge-\(mosaic)-BE\(Int(stops)).dng"))
                }
                let scale = pow(2, stops)
                print("\n== wedge \(mosaic) BE=\(stops) shipped settings (Developer.develop)")
                Self.report(
                    Self.read(try RAWDevelopTests.developer.develop(data).image), chart: chart, cameras: cameras, scale: scale, rows: true)
                print("\n== wedge \(mosaic) BE=\(stops) pre-MOV-79 settings")
                let preMOV79 = try RAWDevelopSupport.preMOV79Negative(RAWDevelopSupport.filter(data))
                Self.report(Self.read(preMOV79.image), chart: chart, cameras: cameras, scale: scale, rows: true)

                for version in try RAWDevelopSupport.filter(data).supportedDecoderVersions {
                    var first = true
                    for edr in Self.edrAmounts {
                        for gamut in [true, false] {
                            for hr in [true, false] {
                                let settings = Settings(edr: edr, gamutMapping: gamut, highlightRecovery: hr, decoder: version)
                                let raw = try RAWDevelopSupport.filter(data)
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

    @Test func shadowBias() throws {
        let chart = PatchChart(RAWDevelopChart.scene)
        let cameras = RAWDevelopChart.cameraValues(RAWDevelopChart.scene)
        print("\n#### RAW probe: shadowBias (EDR 2, gamut mapping off, highlight recovery on, default decoder)")
        for mosaic in SyntheticDNG.Mosaic.allCases {
            for stops in Self.baselineStopsSweep {
                let data = RAWDevelopChart.dng(mosaic, chart: chart, baselineStops: stops)
                for bias: Float? in [nil, 0] {
                    let raw = try RAWDevelopSupport.filter(data)
                    Self.apply(Settings(edr: 2, gamutMapping: false, highlightRecovery: true), raw)
                    let defaultBias = raw.shadowBias
                    if let bias { raw.shadowBias = bias }
                    print("\n== shadowBias \(mosaic) BE=\(stops) shadowBias=\(raw.shadowBias) (default \(defaultBias))")
                    Self.report(try #require(Self.read(raw)), chart: chart, cameras: cameras, scale: pow(2, stops), rows: false)
                }
            }
        }
    }

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
            let fresh = try RAWDevelopSupport.filter(data)
            print(
                "\n== \(mosaic) default decoderVersion on a new filter: \(fresh.decoderVersion.rawValue) of \(fresh.supportedDecoderVersions.map(\.rawValue))"
            )
            var firstVersion: [SIMD3<Double>]?
            for version in fresh.supportedDecoderVersions {
                var engine: [SIMD3<Double>]?
                for (name, context) in contexts {
                    let raw = try RAWDevelopSupport.filter(data)
                    Self.apply(Settings(decoder: version), raw)
                    let start = ContinuousClock.now
                    guard let image = raw.outputImage, !image.extent.isInfinite, !image.extent.isEmpty else {
                        print("  \(version.rawValue) \(name): outputImage nil")
                        continue
                    }
                    let values = Self.rgba(image, context: context)
                    let ms = start.duration(to: .now).milliseconds
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
}
