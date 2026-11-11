import EmulsionCore
import Foundation
import Observation

/// Saved looks are separate from the photo library. A failed read never enables an overwrite.
@MainActor @Observable
public final class RecipeStore {
    public private(set) var recipes: [Recipe] = []
    public private(set) var loadError: EmulsionError?
    private let folder: URL
    private var indexURL: URL { folder.appending(path: "recipes.json") }
    private static let maximumRecipes = 256
    private static let maximumIndexSize = 4_194_304

    public convenience init() {
        self.init(folder: URL.applicationSupportDirectory.appending(path: "Emulsion", directoryHint: .isDirectory))
    }

    init(folder: URL) {
        self.folder = folder
        do {
            let data = try Self.read(indexURL, limit: Self.maximumIndexSize)
            let loaded = try JSONDecoder().decode([Recipe].self, from: data)
            guard loaded.count <= Self.maximumRecipes, Set(loaded.map(\.id)).count == loaded.count else {
                throw EmulsionError.recipesUnreadable
            }
            recipes = loaded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // A new collection, not an unreadable one.
        } catch {
            loadError = .recipesUnreadable
        }
    }

    @discardableResult
    public func save(name: String, adjustments: Adjustments) throws -> Recipe {
        let recipe = try Recipe(name: name, adjustments: adjustments)
        try commit(recipes + [recipe])
        return recipe
    }

    /// Imported identity never overwrites a saved or curated look. Importing does not apply it.
    @discardableResult
    public func importRecipe(_ data: Data) throws -> Recipe {
        let imported = try Recipe.decode(data)
        let recipe = try Recipe(name: imported.name, summary: imported.summary, adjustments: imported.adjustments)
        try commit(recipes + [recipe])
        return recipe
    }

    @discardableResult
    public func importRecipe(at url: URL) throws -> Recipe {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try importRecipe(Self.read(url, limit: Recipe.maximumFileSize))
    }

    public func delete(_ recipe: Recipe) throws {
        try commit(recipes.filter { $0.id != recipe.id })
    }

    private func commit(_ updated: [Recipe]) throws(EmulsionError) {
        guard loadError == nil else { throw .recipesUnreadable }
        guard updated.count <= Self.maximumRecipes else { throw .recipeSaveFailed }
        do {
            let data = try JSONEncoder().encode(updated)
            guard data.count <= Self.maximumIndexSize else { throw EmulsionError.recipeSaveFailed }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: indexURL, options: .atomic)
        } catch { throw .recipeSaveFailed }
        recipes = updated
    }

    /// Bounded reads also cover providers that don't report a reliable file size.
    private static func read(_ url: URL, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw EmulsionError.invalidRecipe }
        return data
    }
}
