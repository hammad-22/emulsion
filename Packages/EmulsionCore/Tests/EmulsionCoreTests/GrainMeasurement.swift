import Accelerate
import CoreImage
import EmulsionFixtures
import Foundation
import simd

@testable import EmulsionCore

/// Statistics for the grain tests and proof (MOV-30): moments, correlations, area reduction and
/// radially averaged periodograms. Arrays are fields stored row by row, `width` values per row.
enum GrainMeasurement {
    static func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }

    static func standardDeviation(_ v: [Double]) -> Double {
        let m = mean(v)
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
    }

    /// Fourth standardized moment minus 3 (0 for a Gaussian, −1.2 for a uniform).
    static func excessKurtosis(_ v: [Double]) -> Double {
        let m = mean(v)
        let (m2, m4) = v.reduce((0.0, 0.0)) { sums, x in
            let d2 = (x - m) * (x - m)
            return (sums.0 + d2, sums.1 + d2 * d2)
        }
        let n = Double(v.count)
        return (m4 / n) / ((m2 / n) * (m2 / n)) - 3
    }

    static func correlation(_ x: [Double], _ y: [Double]) -> Double {
        let (mx, my) = (mean(x), mean(y))
        var (sxy, sxx, syy) = (0.0, 0.0, 0.0)
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Correlation between each value and its neighbour `dx` columns and `dy` rows away.
    static func lagCorrelation(_ v: [Double], width: Int, height: Int, dx: Int, dy: Int) -> Double {
        var (a, b) = ([Double](), [Double]())
        a.reserveCapacity(v.count)
        b.reserveCapacity(v.count)
        for y in 0..<(height - dy) {
            for x in 0..<(width - dx) {
                a.append(v[y * width + x])
                b.append(v[(y + dy) * width + x + dx])
            }
        }
        return correlation(a, b)
    }

    /// P3 encoding (the sRGB transfer function) of display-linear values, ×255.
    static func codes(_ linear: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(Fixtures.encode(linear.x), Fixtures.encode(linear.y), Fixtures.encode(linear.z)) * 255
    }

    /// Area (box) reduction by `scale` source pixels per output pixel, `outWidth`×`outHeight` output
    /// pixels, the first starting `origin` source pixels into the source (both axes): each output pixel is the mean of the source over its square,
    /// partial source pixels weighted by their overlap. Also returns the mean over output pixels of
    /// Σw² (the variance a white field keeps; 1/scale² only when `scale` is whole).
    static func areaReduced(
        _ source: [SIMD3<Double>], width: Int, origin: Double = 0, scale: Double, outWidth: Int, outHeight: Int
    ) -> (values: [SIMD3<Double>], meanSquaredWeight: Double) {
        func weights(_ i: Int) -> [(index: Int, weight: Double)] {
            let (lo, hi) = (origin + Double(i) * scale, origin + Double(i + 1) * scale)
            return (Int(lo.rounded(.down))..<Int(hi.rounded(.up))).map { j in
                (j, (min(Double(j + 1), hi) - max(Double(j), lo)) / scale)
            }
        }
        let columns = (0..<outWidth).map(weights)
        let rows = (0..<outHeight).map(weights)
        var values = [SIMD3<Double>](repeating: .zero, count: outWidth * outHeight)
        var squared = 0.0
        for (oy, row) in rows.enumerated() {
            for (ox, column) in columns.enumerated() {
                var sum = SIMD3<Double>.zero
                for (y, wy) in row {
                    for (x, wx) in column { sum += source[y * width + x] * (wx * wy) }
                }
                values[oy * outWidth + ox] = sum
                squared += row.reduce(0) { $0 + $1.weight * $1.weight } * column.reduce(0) { $0 + $1.weight * $1.weight }
            }
        }
        return (values, squared / Double(outWidth * outHeight))
    }

    /// Radially averaged periodogram |DFT|²/N² of `block`×`block` tiles (each tile's mean removed),
    /// averaged over the tiles that fit, in `bands` equal bands of radial frequency from 0 to 0.5
    /// cycles per pixel (DC excluded). A white field of variance σ² gives σ² in every band.
    static func radialPowerSpectrum(_ v: [Double], width: Int, height: Int, block: Int = 64, bands: Int = 10)
        -> [(frequency: Double, power: Double)]
    {
        guard
            let dft = try? vDSP.DiscreteFourierTransform(
                previousDFT: nil, count: block, direction: .forward, transformType: .complexComplex, ofType: Double.self)
        else { return [] }
        var sums = [Double](repeating: 0, count: bands)
        var counts = [Double](repeating: 0, count: bands)
        let n = Double(block * block)
        for by in 0..<(height / block) {
            for bx in 0..<(width / block) {
                var tile = [Double](repeating: 0, count: block * block)
                for y in 0..<block {
                    for x in 0..<block { tile[y * block + x] = v[(by * block + y) * width + bx * block + x] }
                }
                let m = mean(tile)
                var re = tile.map { $0 - m }
                var im = [Double](repeating: 0, count: block * block)
                for pass in 0..<2 {
                    for line in 0..<block {
                        let indices = (0..<block).map { pass == 0 ? line * block + $0 : $0 * block + line }
                        let (outRe, outIm) = dft.transform(real: indices.map { re[$0] }, imaginary: indices.map { im[$0] })
                        for (k, i) in indices.enumerated() { (re[i], im[i]) = (outRe[k], outIm[k]) }
                    }
                }
                for fy in 0..<block {
                    for fx in 0..<block where fx != 0 || fy != 0 {
                        let u = Double(fx <= block / 2 ? fx : fx - block) / Double(block)
                        let w = Double(fy <= block / 2 ? fy : fy - block) / Double(block)
                        let band = Int((u * u + w * w).squareRoot() / 0.5 * Double(bands))
                        guard band < bands else { continue }
                        let i = fy * block + fx
                        sums[band] += (re[i] * re[i] + im[i] * im[i]) / n
                        counts[band] += 1
                    }
                }
            }
        }
        return (0..<bands).map { band -> (frequency: Double, power: Double) in
            let frequency: Double = (Double(band) + 0.5) * 0.5 / Double(bands)
            let power: Double = sums[band] / max(counts[band], 1)
            return (frequency, power)
        }
    }

    // MARK: Renders

    /// A uniform neutral scene `stops` from mid-gray.
    static func flat(stops: Double, width: Int, height: Int) -> CIImage {
        SceneFixtures.flat(0.18 * pow(2, stops), width: width, height: height)
    }

    /// Display-linear P3 values of the `size`×`size` square at (`x`, `y`) in `image`.
    static func linearCrop(_ image: CIImage, x: Int = 0, y: Int = 0, size: Int) -> [SIMD3<Double>] {
        Fixtures.encodedFloats(image.cropped(to: CGRect(x: x, y: y, width: size, height: size)), space: SceneFixtures.linearP3)
    }

    /// Standard deviation of display luma in codes.
    static func lumaSD(_ linear: [SIMD3<Double>]) -> Double { standardDeviation(linear.map { EmulsionTestCase.luma(codes($0)) }) }

    /// Standard deviation per channel, in codes.
    static func channelSD(_ linear: [SIMD3<Double>]) -> SIMD3<Double> {
        let c = linear.map(codes)
        return SIMD3((0..<3).map { i in standardDeviation(c.map { $0[i] }) })
    }

    /// Display σ per channel (codes) that the Swift mirror predicts for a flat neutral patch `stops`
    /// from mid-gray: Monte Carlo over negative density offsets N(0, σ²) per layer, σ from `Grain`,
    /// through `FilmModel.render`, clamped to 0…1 (the kernel's gamut fit clamps lightness).
    static func predictedDisplaySD(stops: Double, amount: Double, longEdge: Double, samples: Int = 200_000) -> SIMD3<Double> {
        let model = FilmLook.stock
        let scene = SIMD3(repeating: 0.18 * pow(2, stops))
        let sigma = Grain.densitySigma(logExposure: model.layerLogExposure(scene), amount: amount, longEdge: longEdge)
        var random = GaussianSequence(seed: 0x5EED_0030)
        let prints = (0..<samples).map { _ in
            simd_clamp(model.render(scene, grain: sigma * SIMD3(random.next(), random.next(), random.next())), .zero, .one)
        }
        return channelSD(prints)
    }

    /// Standard normal values, deterministic for a seed (SplitMix64 and Box–Muller).
    struct GaussianSequence {
        private var state: UInt64
        private var spare: Double?

        init(seed: UInt64) { state = seed }

        private mutating func uniform() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return (Double((z ^ (z >> 31)) >> 11) + 0.5) / Double(1 << 53)
        }

        mutating func next() -> Double {
            if let s = spare {
                spare = nil
                return s
            }
            let (r, angle) = ((-2 * log(uniform())).squareRoot(), 2 * Double.pi * uniform())
            spare = r * sin(angle)
            return r * cos(angle)
        }
    }

    /// Display-luma σ of a preview against the full-size render reduced to the preview's size.
    struct PreviewExport {
        let previewLongEdge: Int
        /// Full-size pixels per preview pixel.
        let scale: Double
        let preview, export, area, lanczos: Double
        /// scale²·mean Σw² of the area reduction: the share of a white field's variance it keeps
        /// relative to a continuous aperture of the preview pixel (1 only for whole scales).
        let areaWhiteVarianceFactor: Double

        var areaRatio: Double { preview / area }
        /// The area ratio for white grain: the box's partial pixels average less than a continuous
        /// aperture would, so its σ is divided by √factor.
        var areaRatioWhite: Double { preview / (area / areaWhiteVarianceFactor.squareRoot()) }
        var lanczosRatio: Double { preview / lanczos }
        /// Preview σ against Selwyn's prediction from the full-size σ (σ ∝ 1/pixel side).
        var selwynRatio: Double { preview / (export / scale) }
    }

    /// Mid-gray at 4032×3024 against previews of `edges`, display luma in codes over `crop`² preview
    /// pixels away from the borders (resampling darkens edge pixels).
    static func previewExport(
        _ renderer: Renderer, edges: [Int] = [1179, 1600, 2556], grain: Double = 1, seed: Double = 9, crop: Int = 256
    ) throws -> [PreviewExport] {
        let (w, h, margin) = (4032, 3024, 64)
        var a = Adjustments.neutral
        (a.grain, a.seed) = (grain, seed)
        let negative = Negative(image: flat(stops: 0, width: w, height: h), contract: .sceneReferred)
        let export = try renderer.render(negative, a)
        let exportSD = lumaSD(linearCrop(export, x: margin, y: margin, size: crop))
        return try edges.map { edge in
            let scale = Double(w) / Double(edge)
            let preview = try renderer.render(renderer.resized(negative, longestEdge: CGFloat(edge)), a)
            let start = Double(margin) * scale
            let sourceOrigin = Int(start.rounded(.down))
            let sourceSide = Int((Double(crop) * scale).rounded(.up)) + 2
            let reduced = areaReduced(
                linearCrop(export, x: sourceOrigin, y: sourceOrigin, size: sourceSide), width: sourceSide,
                origin: start - Double(sourceOrigin), scale: scale, outWidth: crop, outHeight: crop)
            return PreviewExport(
                previewLongEdge: edge, scale: scale, preview: lumaSD(linearCrop(preview, x: margin, y: margin, size: crop)),
                export: exportSD, area: lumaSD(reduced.values),
                lanczos: lumaSD(linearCrop(export.lanczosScaled(by: 1 / scale), x: margin, y: margin, size: crop)),
                areaWhiteVarianceFactor: scale * scale * reduced.meanSquaredWeight)
        }
    }
}
