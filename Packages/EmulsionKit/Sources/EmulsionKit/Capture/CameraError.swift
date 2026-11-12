import Foundation

/// Why the camera can't start or a capture didn't make it into the library.
/// Lives here rather than in `EmulsionError` because it's app logic, not engine.
public enum CameraError: LocalizedError, Equatable, Sendable {
    case notAuthorized, unavailable, rawUnsupported, captureFailed
    /// Captured, but the library couldn't store it.
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(localized: "Emulsion doesn't have access to the camera. You can allow it in Settings.", bundle: .module)
        case .unavailable: String(localized: "The camera isn't available right now.", bundle: .module)
        case .rawUnsupported: String(localized: "This camera can't capture RAW photos.", bundle: .module)
        case .captureFailed: String(localized: "The photo couldn't be taken. Try again.", bundle: .module)
        case .saveFailed:
            String(localized: "The photo was taken but couldn't be saved. Check that there's free storage space.", bundle: .module)
        }
    }
}
