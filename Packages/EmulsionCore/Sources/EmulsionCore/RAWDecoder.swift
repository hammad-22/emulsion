import CoreImage
import Foundation

/// Apple's RAW decoder kept alive for one file, so developing it again at another white balance
/// neither reads nor decodes the file again (MOV-137): only the white balance and what follows it
/// are rendered. It holds the file's bytes and the decoder's caches, so keep one, for the photo
/// being edited. Not thread-safe: use it from one actor.
public final class RAWDecoder {
    private let raw: CIRAWFilter
    /// The file's own neutral, to return to as shot exactly (a temperature and tint read back
    /// from the filter are rounded).
    private let asShotNeutral: CGPoint
    public let asShotWhiteBalance: CameraWhiteBalance
    /// Measured or given once, as shot, when the decoder was made; the same at every white balance.
    public let exposureAnchorStops: Double

    /// `raw` is configured for the develop (rendering bypassed, preview scale set) and still as shot.
    init(_ raw: CIRAWFilter, exposureAnchorStops: Double) {
        self.raw = raw
        self.exposureAnchorStops = exposureAnchorStops
        asShotNeutral = raw.neutralChromaticity
        asShotWhiteBalance = Self.whiteBalance(of: raw)
    }

    /// The file developed at `whiteBalance` (clamped to Apple's ranges); nil is as shot.
    public func negative(whiteBalance: CameraWhiteBalance? = nil) throws -> Negative {
        // Setting the neutral doesn't make the filter decode the file again (measured, MOV-10).
        if let whiteBalance = whiteBalance?.clamped() {
            raw.neutralTemperature = Float(whiteBalance.temperature)
            raw.neutralTint = Float(whiteBalance.tint)
        } else {
            raw.neutralChromaticity = asShotNeutral
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
