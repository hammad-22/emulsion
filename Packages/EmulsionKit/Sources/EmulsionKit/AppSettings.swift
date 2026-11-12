import EmulsionCore
import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
public final class AppSettings {
    public enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case standard, full
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .standard: String(localized: "12 MP", bundle: .module, comment: "Capture resolution in megapixels")
            case .full: String(localized: "48 MP", bundle: .module, comment: "Capture resolution in megapixels")
            }
        }
    }

    private enum Key {
        static let autoSave = "autoSave", format = "format", resolution = "resolution", recipe = "cameraRecipe"
    }

    public var autoSave: Bool { didSet { defaults.set(autoSave, forKey: Key.autoSave) } }
    public var format: Renderer.ExportFormat { didSet { defaults.set(format.rawValue, forKey: Key.format) } }
    /// The camera's capture resolution; lenses without 48 MP capture at 12 MP.
    public var resolution: Resolution { didSet { defaults.set(resolution.rawValue, forKey: Key.resolution) } }
    /// The camera's recipe, kept as a snapshot (its encoded JSON), like a photo's edit: it
    /// survives the recipe being deleted from the saved looks. Missing or unreadable reads as the
    /// first curated look.
    public var recipe: Recipe { didSet { defaults.set(try? recipe.encoded(), forKey: Key.recipe) } }

    private let defaults: UserDefaults

    /// `defaults` is the store (tests pass their own suite).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoSave = defaults.bool(forKey: Key.autoSave)
        format = Renderer.ExportFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .heic
        resolution = Resolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .standard
        recipe = defaults.data(forKey: Key.recipe).flatMap { try? Recipe.decode($0) } ?? Self.defaultRecipe
    }

    /// The first curated look ("Everyday", the default adjustments).
    static var defaultRecipe: Recipe {
        guard let first = CuratedLooks.recipes.first else {
            // CuratedLooks is a constant, non-empty list (EmulsionCore's RecipeTests).
            preconditionFailure("Emulsion ships curated looks")
        }
        return first
    }
}
