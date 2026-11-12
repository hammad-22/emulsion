import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

extension Developer {
    /// A camera viewfinder frame (display-linear, working space) → an approximate preview of the
    /// scene estimate `sceneFromDisplay` makes, tagged `.previewEstimate` so it is printed
    /// absolutely, like the RAW capture it previews. Captures always develop from RAW.
    ///
    /// `sceneFromDisplay` bisects every pixel, which the live preview must not do (AGENTS.md).
    /// Its estimate is one per-channel curve in linear P3 (soft ends, then the inverse neutral
    /// print) followed by the inverse layer sensitivity, so this applies the curve, sampled once
    /// from the Swift mirror, with the built-in `CIColorCurves`, and the matrix with
    /// `CIColorMatrix`. No per-pixel iteration.
    public func viewfinderNegative(from image: CIImage) -> Negative {
        Negative(image: Self.viewfinderEstimate.apply(to: image), contract: .previewEstimate)
    }

    /// Sampled once per process from the stock the renderer prints with.
    private static let viewfinderEstimate = ViewfinderEstimate(model: FilmLook.stock)
}

/// The approximate preview inverse behind `Developer.viewfinderNegative(from:)`.
///
/// `CIColorCurves` looks the table up in extended Display P3, whose sRGB-shaped encoding spaces
/// the steps by lightness instead of linear light, so the deep shadows (the floor is −9 stops)
/// aren't coarse. Table values are encoded the same way and the filter decodes them back; it
/// doesn't clamp them, so white keeps its +4-stop estimate. Its input is clamped to the table's
/// domain, 0…1, as the kernel clamps display values, and alpha passes through
/// (`ViewfinderEstimateTests`).
struct ViewfinderEstimate {
    /// Table steps across encoded display 0…1. Measured on the gray ramp, the estimate is within
    /// 0.003 stops of the exact one at 1024 steps (0.03 at 256, 0.08 at 128), for a 12 KB table.
    static let steps = 1024
    private let table: Data
    /// P3 → working · sensitivity⁻¹ · working → P3, as `CIColorMatrix` rows: the curve's
    /// per-layer exposures become the scene estimate in the working space.
    private let rows: [CIVector]

    private static let filterSpace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)!

    init(model: FilmModel) {
        let ends = model.softEnds
        let display = InputColorSpace.displayP3
        let exposures = (0..<Self.steps).map {
            model.layerExposure(fromDisplay: display.decode(signal: Double($0) / Double(Self.steps - 1)), ends: ends)
        }
        table = exposures.map { Float(Self.encode($0)) }.flatMap { [$0, $0, $0] }.withUnsafeBytes { Data($0) }
        let toWorking = InputColorSpace.displayP3.toWorking
        let m = toWorking * model.sensitivity.inverse * toWorking.inverse
        rows = CIVector.rows(of: m)
    }

    func apply(to image: CIImage) -> CIImage {
        let curves = CIFilter.colorCurves()
        curves.inputImage = image
        curves.curvesData = table
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.colorSpace = Self.filterSpace
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = curves.outputImage
        matrix.rVector = rows[0]
        matrix.gVector = rows[1]
        matrix.bVector = rows[2]
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return (matrix.outputImage ?? image).cropped(to: image.extent)
    }

    /// The sRGB transfer function (IEC 61966-2-1), which extended Display P3 uses.
    /// The engine decodes it (`InputColorSpace.displayP3`) but never encodes, so this is the one
    /// encoder.
    private static func encode(_ linear: Double) -> Double {
        linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }
}
