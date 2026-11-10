import Foundation

public enum EmulsionError: LocalizedError {
    case unsupportedPhoto, unsupportedVideoFormat, renderFailed, kernelsMissing
    case libraryUnreadable, librarySaveFailed
    public var errorDescription: String? {
        switch self {
        case .unsupportedPhoto: return "This photo format isn't supported."
        case .unsupportedVideoFormat: return "This video format isn't supported."
        case .renderFailed: return "The photo couldn't be rendered."
        case .kernelsMissing: return "Emulsion's image kernels are missing from the app bundle."
        case .libraryUnreadable:
            return "Emulsion couldn't read its library, so your photos are shown with the default look. The old library file was kept."
        case .librarySaveFailed: return "Your changes couldn't be saved. Check that there's free storage space."
        }
    }
}
