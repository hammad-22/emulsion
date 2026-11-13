import Accelerate
import Foundation

/// Grain measured the way film granularity is: fluctuations of density on a uniformly exposed
/// patch. Here the density is the rendered print's visual density, −log10 of its display luminance
/// (relative to display white), not a Status A or diffuse density of a real print.
/// - RMS granularity σ(D): the standard deviation of density on the patch (Kodak and ISO 6328
///   measure it through a 48 µm aperture; here it is per pixel, so values depend on resolution).
/// - Noise power spectrum (Wiener spectrum): the squared Fourier transform of the density
///   fluctuations, averaged over square tiles and radially, in density² · pixel². Its mean over
///   every frequency is the variance (Parseval), so the spectrum shows how σ(D)² spreads over
///   grain sizes.
enum GrainStatistics {
    /// Tile edge for the spectrum, a power of two; frequencies step by 1 / `tile` cycles per pixel.
    static let tile = 64

    struct Patch: Codable {
        let meanDensity: Double
        let rmsDensity: Double
        /// Radially averaged noise power, bin k at k / `tile` cycles per pixel, k = 0…tile/2.
        let noisePower: [Double]

        init(densities: [Double], width: Int, height: Int) {
            meanDensity = vDSP.mean(densities)
            rmsDensity = (vDSP.meanSquare(vDSP.add(-meanDensity, densities))).squareRoot()
            noisePower = GrainStatistics.noisePowerSpectrum(densities, width: width, height: height)
        }

        /// Noise power at the highest frequency bins (0.375–0.5 cycles per pixel) over the low ones
        /// (1/tile–0.125, the zero bin excluded): about 1 for white noise, smaller for grain that
        /// spans several pixels.
        var highToLowPower: Double {
            let n = noisePower.count - 1
            let low = noisePower[1...(n / 4)]
            let high = noisePower[(3 * n / 4)...n]
            return (high.reduce(0, +) / Double(high.count)) / max(low.reduce(0, +) / Double(low.count), .leastNonzeroMagnitude)
        }
    }

    /// Luminance floor before −log10, so black reads as density 6, not infinity.
    static let darkestLuminance = 1e-6

    /// The patch's statistics, from −log10 of display luminance per pixel.
    static func patch(_ image: RegressionImage) -> Patch {
        let densities = image.encoded.map { -log10(max(ColorDifference.xyz(fromDisplayP3: $0).y, darkestLuminance)) }
        return Patch(densities: densities, width: image.width, height: image.height)
    }

    /// Mean of |FFT|² / tile² over every whole `tile` × `tile` tile (each with its own mean removed),
    /// radially averaged. Bins are k / `tile` cycles per pixel for k = 0…tile/2; corner frequencies
    /// beyond 0.5 cycles per pixel are left out.
    static func noisePowerSpectrum(_ plane: [Double], width: Int, height: Int) -> [Double] {
        precondition(width >= tile && height >= tile, "patch smaller than one \(tile)-pixel tile")
        let log2n = vDSP_Length(tile.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { preconditionFailure("FFT setup failed") }
        defer { vDSP_destroy_fftsetupD(setup) }
        let n = tile * tile
        var power = [Double](repeating: 0, count: n)
        var tiles = 0
        var real = [Double](repeating: 0, count: n)
        var imaginary = [Double](repeating: 0, count: n)
        for top in stride(from: 0, through: height - tile, by: tile) {
            for left in stride(from: 0, through: width - tile, by: tile) {
                for row in 0..<tile {
                    let start = (top + row) * width + left
                    real.replaceSubrange(row * tile..<(row + 1) * tile, with: plane[start..<start + tile])
                }
                vDSP.add(-vDSP.mean(real), real, result: &real)
                vDSP.fill(&imaginary, with: 0)
                real.withUnsafeMutableBufferPointer { re in
                    imaginary.withUnsafeMutableBufferPointer { im in
                        guard let realp = re.baseAddress, let imagp = im.baseAddress else { return }
                        var split = DSPDoubleSplitComplex(realp: realp, imagp: imagp)
                        vDSP_fft2d_zipD(setup, &split, 1, 0, log2n, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
                vDSP.add(power, vDSP.multiply(1 / Double(n), vDSP.add(vDSP.square(real), vDSP.square(imaginary))), result: &power)
                tiles += 1
            }
        }
        var sums = [Double](repeating: 0, count: tile / 2 + 1)
        var counts = [Int](repeating: 0, count: tile / 2 + 1)
        for v in 0..<tile {
            for u in 0..<tile {
                let (fu, fv) = (min(u, tile - u), min(v, tile - v))
                let bin = Int((Double(fu * fu + fv * fv).squareRoot()).rounded())
                guard bin <= tile / 2 else { continue }
                sums[bin] += power[v * tile + u] / Double(tiles)
                counts[bin] += 1
            }
        }
        return zip(sums, counts).map { $0 / Double($1) }
    }
}
