import Foundation

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

public struct LensOption: Sendable, Equatable, Identifiable {
    public let lens: CameraLens
    /// Relative to the wide lens: 0.5 for an ultra wide.
    public let magnification: Double
    public var id: CameraLens { lens }

    init(lens: CameraLens, magnification: Double) {
        self.lens = lens
        self.magnification = magnification
    }

    public func title(isSelected: Bool) -> String {
        let number = formattedMagnification
        return isSelected ? String(localized: "\(number)×", bundle: .module, comment: "Selected lens magnification") : number
    }

    public var accessibilityLabel: String {
        String(localized: "\(lens.title), \(formattedMagnification)×", bundle: .module, comment: "Lens name and magnification")
    }

    private var formattedMagnification: String { displayedMagnification.formatted(.number.precision(.fractionLength(0...1))) }

    /// Rounded like the system Camera's labels: tenths below 1×, halves above (4, not 4.2).
    var displayedMagnification: Double {
        magnification < 1 ? (magnification * 10).rounded() / 10 : (magnification * 2).rounded() / 2
    }
}
