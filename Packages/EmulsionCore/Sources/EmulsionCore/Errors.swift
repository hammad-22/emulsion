import Foundation

public enum EmulsionError: LocalizedError {
    case unsupportedPhoto, unsupportedVideoFormat, renderFailed, kernelsMissing
    public var errorDescription: String? {
        switch self {
        case .unsupportedPhoto: return "This photo format isn't supported."
        case .unsupportedVideoFormat: return "This video format isn't supported."
        case .renderFailed: return "The photo couldn't be rendered."
        case .kernelsMissing: return "Emulsion's image kernels are missing from the app bundle."
        }
    }
}
