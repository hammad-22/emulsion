import Foundation

public enum RAWFormat: Sendable {
    /// Demosaiced and multi-frame processed, still scene-referred ("Linear DNG").
    case proRAW
    case bayer

    public var title: String {
        switch self {
        case .proRAW: String(localized: "ProRAW", bundle: .module, comment: "Apple ProRAW capture format badge")
        case .bayer: String(localized: "RAW", bundle: .module, comment: "Bayer RAW capture format badge")
        }
    }

    static func preferred(proRAWAvailable: Bool, bayerAvailable: Bool) throws(CameraError) -> RAWFormat {
        if proRAWAvailable { return .proRAW }
        if bayerAvailable { return .bayer }
        throw .rawUnsupported
    }
}
