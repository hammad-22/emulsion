import CoreImage
import Foundation

/// Apple's RAW decoder kept alive for one file, so developing it again at another white balance
/// neither reads nor decodes the file again (MOV-137): only the white balance and what follows it
/// are rendered. It holds the file's bytes and the decoder's caches, so keep one, for the photo
/// being edited. Not thread-safe: use it from one actor.
public final class RAWDecoder {
    private let raw: CIRAWFilter
    /// The neutral as the filter reported it before anything set it.
    private let asShot: (temperature: Float, tint: Float)
    /// An untouched filter develops the file's own neutral, which setting it doesn't reproduce
    /// bit for bit, so as shot is only set again after another white balance was.
    private var hasSetNeutral = false
    let asShotWhiteBalance: CameraWhiteBalance
    /// Measured or given once, as shot, when the decoder was made; the same at every white balance.
    public let exposureAnchorStops: Double

    /// `raw` is configured for the develop (rendering bypassed, preview scale set) and still as shot.
    init(_ raw: CIRAWFilter, exposureAnchorStops: Double) {
        self.raw = raw
        self.exposureAnchorStops = exposureAnchorStops
        asShot = (raw.neutralTemperature, raw.neutralTint)
        asShotWhiteBalance = Self.whiteBalance(of: raw)
    }

    /// The file developed at `whiteBalance` (clamped to Apple's ranges); nil is as shot. Back at
    /// as shot after another white balance it develops within 1e-6 of the untouched file (measured
    /// on synthetic linear and Bayer DNGs, MOV-137).
    public func negative(whiteBalance: CameraWhiteBalance? = nil) throws -> Negative {
        // Setting the neutral doesn't make the filter decode the file again (measured, MOV-10).
        if let whiteBalance = whiteBalance?.clamped() {
            raw.neutralTemperature = Float(whiteBalance.temperature)
            raw.neutralTint = Float(whiteBalance.tint)
            hasSetNeutral = true
        } else if hasSetNeutral {
            raw.neutralTemperature = asShot.temperature
            raw.neutralTint = asShot.tint
        }
        guard var output = raw.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else {
            throw EmulsionError.unsupportedPhoto
        }
        if exposureAnchorStops != 0 {
            output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposureAnchorStops])
        }
        return Negative(
            image: Developer.normalized(output), contract: .sceneReferred, exposureAnchorStops: exposureAnchorStops,
            asShotWhiteBalance: asShotWhiteBalance)
    }

    /// The temperature and tint the decoder is set to: as shot on a filter nothing has changed.
    static func whiteBalance(of raw: CIRAWFilter) -> CameraWhiteBalance {
        CameraWhiteBalance(temperature: Double(raw.neutralTemperature), tint: Double(raw.neutralTint))
    }
}
