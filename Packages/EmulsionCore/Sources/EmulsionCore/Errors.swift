import Foundation

public enum EmulsionError: LocalizedError, Equatable {
    case unsupportedPhoto, unsupportedVideoFormat, renderFailed, kernelsMissing
    /// A stock file or `FilmStock` the engine can't print with. The reason (developer English, not for alerts) is the
    /// `failureReason`.
    case invalidStock(String)
    case libraryUnreadable, librarySaveFailed, libraryDeleteFailed
    case invalidRecipe, recipeVersionUnsupported, recipeModelUnsupported, recipesUnreadable, recipeSaveFailed
    public var errorDescription: String? {
        switch self {
        case .invalidRecipe: return String(localized: "This look file is invalid or contains unsupported adjustments.", bundle: .module)
        case .recipeVersionUnsupported:
            return String(localized: "This look uses an unsupported file version. Try updating Emulsion.", bundle: .module)
        case .recipeModelUnsupported:
            return String(localized: "This look needs a different film model and can't be applied here.", bundle: .module)
        case .recipesUnreadable:
            return String(
                localized: "Your saved looks couldn't be read. The file was kept; saving looks is disabled until it can be read.",
                bundle: .module)
        case .recipeSaveFailed: return String(localized: "This look couldn't be saved. Your saved looks were kept.", bundle: .module)
        case .unsupportedPhoto: return String(localized: "This photo format isn't supported.", bundle: .module)
        case .unsupportedVideoFormat: return String(localized: "This video format isn't supported.", bundle: .module)
        case .renderFailed: return String(localized: "The photo couldn't be rendered.", bundle: .module)
        case .kernelsMissing: return String(localized: "Emulsion's image kernels are missing from the app bundle.", bundle: .module)
        case .invalidStock: return String(localized: "This film stock can't be used.", bundle: .module)
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

    public var failureReason: String? {
        guard case .invalidStock(let reason) = self else { return nil }
        return reason
    }

    /// Description and failure reason together, for logs and developer tools.
    package var developerDescription: String {
        [errorDescription, failureReason].compactMap { $0 }.joined(separator: " ")
    }
}
