import Foundation

/// The kind of RAW file the camera writes. Both are DNG.
public enum RAWFormat: Sendable {
    /// Apple ProRAW: demosaiced, multi-frame processed, still scene-referred ("Linear DNG").
    case proRAW
    /// The sensor's own mosaic, single frame.
    case bayer

    public var title: String {
        switch self {
        case .proRAW: String(localized: "ProRAW", bundle: .module, comment: "Apple ProRAW capture format badge")
        case .bayer: String(localized: "RAW", bundle: .module, comment: "Bayer RAW capture format badge")
        }
    }

    /// ProRAW when the camera offers it, else Bayer RAW; a camera with neither can't be used.
    static func preferred(proRAWAvailable: Bool, bayerAvailable: Bool) throws(CameraError) -> RAWFormat {
        if proRAWAvailable { return .proRAW }
        if bayerAvailable { return .bayer }
        throw .rawUnsupported
    }
}
