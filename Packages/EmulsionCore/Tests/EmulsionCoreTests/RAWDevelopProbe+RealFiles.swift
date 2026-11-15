import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

extension RAWDevelopProbe {
    static let fullSizeFileCount = 3
    static let daylightKelvin: Float = 5500

    struct DetailedStats {
        let frame: RAWDevelopSupport.FrameStats
        let max: SIMD3<Double>
        let min: Double
        let mean: SIMD3<Double>
        /// Mean R/G and B/G of the brightest 0.1 % of pixels: the colour of clipped highlights.
        let highlightRatios: SIMD2<Double>

        init(_ pixels: [SIMD3<Double>]) {
            let frame = RAWDevelopSupport.FrameStats(pixels)
            self.frame = frame
            max = pixels.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
            min = pixels.map { $0.min() }.min() ?? .nan
            mean = RAWDevelopProbe.mean(pixels)
            let brightest = pixels.filter { RAWDevelopSupport.luminance($0) >= frame.p999 }
            let brightMean = brightest.reduce(SIMD3<Double>.zero, +) / Double(Swift.max(brightest.count, 1))
            highlightRatios = SIMD2(brightMean.x / brightMean.y, brightMean.z / brightMean.y)
        }

        var line: String {
            "max \(max.fourDigits) p99.9 lum \(frame.p999.fourDigits) >1 \(frame.over1.fourDigits) >2 \(frame.over2.fourDigits)"
                + " >4 \(frame.over4.fourDigits) median lum \(frame.medianLuminance.fourDigits) min \(min.fourDigits)"
                + " top-0.1% R/G \(highlightRatios.x.fourDigits) B/G \(highlightRatios.y.fourDigits)"
        }
    }

    /// Sourced: TIFF 6.0, TIFF/EP and DNG.
    private enum TIFF {
        static let newSubFileType = 254
        static let imageWidth = 256
        static let imageLength = 257
        static let bitsPerSample = 258
        static let compression = 259
        static let photometricInterpretation = 262
        static let samplesPerPixel = 277
        static let subIFDs = 330
        static let linearizationTable = 50712
        static let whiteLevel = 50717
        static let rawPhotometrics = [32803, 34892]
        static let typeSizes = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 8: 2, 9: 4, 10: 8, 13: 4]
        static let entrySize = 12
        static let inlineCapacity = 4
        static let printedValues = 8
    }

    /// The full-size raw IFD (NewSubFileType 0), found through the IFD chain and SubIFDs.
    static func rawLayout(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let little = data.prefix(2) == Data("II".utf8)
        func read(_ offset: Int, _ size: Int) -> Int {
            guard offset >= 0, offset + size <= data.count else { return 0 }
            let bytes = data[data.startIndex + offset..<data.startIndex + offset + size]
            return (little ? bytes.reversed() : Array(bytes)).reduce(0) { $0 << 8 | Int($1) }
        }
        var queue = [read(4, 4)]
        var visited = Set<Int>()
        while let offset = queue.popLast() {
            guard offset > 0, visited.insert(offset).inserted else { continue }
            var tags = [Int: [Int]]()
            let count = read(offset, 2)
            for index in 0..<count {
                let entry = offset + 2 + index * TIFF.entrySize
                let (tag, type, n) = (read(entry, 2), read(entry + 2, 2), read(entry + 4, 4))
                let size = TIFF.typeSizes[type] ?? 1
                let base = size * n <= TIFF.inlineCapacity ? entry + 8 : read(entry + 8, 4)
                tags[tag] = (0..<min(n, TIFF.printedValues)).map { read(base + $0 * size, min(size, 4)) }
            }
            queue += tags[TIFF.subIFDs] ?? []
            queue.append(read(offset + 2 + count * TIFF.entrySize, 4))
            if tags[TIFF.newSubFileType]?.first ?? 0 == 0, let photometric = tags[TIFF.photometricInterpretation]?.first,
                TIFF.rawPhotometrics.contains(photometric)
            {
                return "raw IFD: BitsPerSample \(tags[TIFF.bitsPerSample] ?? []) Photometric \(photometric)"
                    + " Compression \(tags[TIFF.compression] ?? []) SamplesPerPixel \(tags[TIFF.samplesPerPixel] ?? [1])"
                    + " size \(tags[TIFF.imageWidth] ?? [])x\(tags[TIFF.imageLength] ?? []) WhiteLevel \(tags[TIFF.whiteLevel] ?? [])"
                    + " LinearizationTable \(tags[TIFF.linearizationTable] == nil ? "no" : "yes")"
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
                    for edr in Self.edrAmounts {
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
                        + " median lum \(stats.frame.medianLuminance.fourDigits) mean RGB \(stats.mean.fourDigits)")
            }
        }
        try realFullSize(scaledMaxima.sorted { $0.max > $1.max }.prefix(Self.fullSizeFileCount).map(\.url))
        try realWhiteBalance(urls, asShot: asShot)
    }

    func realFullSize(_ urls: [URL]) throws {
        print("\n#### RAW probe: full-size maxima of the \(urls.count) files with the highest scaled maximum")
        for url in urls {
            print("== \(url.deletingPathExtension().lastPathComponent)")
            for edr in Self.edrAmounts {
                for gamut in [true, false] {
                    let raw = try Self.realFilter(url, scaled: false)
                    Self.apply(Settings(edr: edr, gamutMapping: gamut, highlightRecovery: true), raw)
                    let start = ContinuousClock.now
                    guard let image = raw.outputImage else { continue }
                    let max = Self.areaMaximum(image)
                    print(
                        "  FULL SIZE \(image.extent.size) EDR \(edr) GM \(gamut) HR on: max \(max.fourDigits) (\(start.duration(to: .now).milliseconds.fourDigits) ms)"
                    )
                }
            }
        }
    }

    func realWhiteBalance(_ urls: [URL], asShot: [(name: String, temperature: Float)]) throws {
        let tungsten = asShot.sorted { $0.temperature < $1.temperature }.prefix(2)
        let daylight = asShot.sorted { abs($0.temperature - Self.daylightKelvin) < abs($1.temperature - Self.daylightKelvin) }.prefix(2)
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
