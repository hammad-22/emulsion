import Foundation

/// One of the back cameras. Physical cameras only: a virtual camera fuses or switches
/// between them, which RAW capture doesn't allow (see `AVCameraSource`).
public enum CameraLens: String, CaseIterable, Sendable, Identifiable {
    case ultraWide, wide, telephoto
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ultraWide: String(localized: "Ultra Wide", bundle: .module, comment: "Camera lens name")
        case .wide: String(localized: "Wide", bundle: .module, comment: "Camera lens name")
        case .telephoto: String(localized: "Telephoto", bundle: .module, comment: "Camera lens name")
        }
    }
}

/// A lens the device has, and how much it magnifies relative to the wide lens.
public struct LensOption: Sendable, Equatable, Identifiable {
    public let lens: CameraLens
    /// Relative to the wide lens: 0.5 for an ultra wide, 4 for a 4× telephoto.
    public let magnification: Double
    public var id: CameraLens { lens }

    public init(lens: CameraLens, magnification: Double) {
        self.lens = lens
        self.magnification = magnification
    }

    /// The magnification as the system Camera shows it: "0.5", "1", "4", with "×" on the
    /// selected lens.
    public func title(isSelected: Bool) -> String {
        let number = displayedMagnification.formatted(.number.precision(.fractionLength(0...1)))
        return isSelected ? String(localized: "\(number)×", bundle: .module, comment: "Selected lens magnification") : number
    }

    /// For VoiceOver: "Ultra Wide, 0.5×".
    public var accessibilityLabel: String {
        let number = displayedMagnification.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(lens.title), \(number)×", bundle: .module, comment: "Lens name and magnification")
    }

    /// Lenses below 1× read in tenths (0.5); longer ones in halves, so a 100 mm lens on a
    /// 24 mm wide reads 4, not 4.2, like the system Camera's labels.
    var displayedMagnification: Double {
        magnification < 1 ? (magnification * 10).rounded() / 10 : (magnification * 2).rounded() / 2
    }
}
