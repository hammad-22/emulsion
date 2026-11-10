import Foundation

public enum EmulsionError: LocalizedError {
    case unsupportedPhoto, unsupportedVideoFormat, renderFailed, kernelsMissing
    case libraryUnreadable, librarySaveFailed, libraryDeleteFailed
    public var errorDescription: String? {
        switch self {
        case .unsupportedPhoto: return String(localized: "This photo format isn't supported.", bundle: .module)
        case .unsupportedVideoFormat: return String(localized: "This video format isn't supported.", bundle: .module)
        case .renderFailed: return String(localized: "The photo couldn't be rendered.", bundle: .module)
        case .kernelsMissing: return String(localized: "Emulsion's image kernels are missing from the app bundle.", bundle: .module)
        case .libraryUnreadable:
            return String(
                localized:
                    "Emulsion couldn't read part of its library. Your original files were kept, but some recovered photos may use the default look.",
                bundle: .module)
        case .librarySaveFailed:
            return String(localized: "Your changes couldn't be saved. Check that there's free storage space.", bundle: .module)
        case .libraryDeleteFailed:
            return String(localized: "The photo was removed from the library, but its original file couldn't be deleted.", bundle: .module)
        }
    }
}
