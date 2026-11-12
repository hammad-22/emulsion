import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct RecipeStoreTests {
    @Test func persistenceImportAndDeleteRoundTrip() throws {
        let library = TestLibrary()
        let store = RecipeStore(folder: library.folder)
        var settings = Adjustments()
        settings.warmth = 0.4
        settings.seed = 567
        let saved = try store.save(name: "My Look", adjustments: settings)
        let imported = try store.importRecipe(saved.encoded())
        #expect(imported.id != saved.id)
        #expect(imported.adjustments == saved.adjustments)
        #expect(RecipeStore(folder: library.folder).recipes == [saved, imported])
        try store.delete(saved)
        #expect(RecipeStore(folder: library.folder).recipes == [imported])
    }

    @Test func failedImportKeepsRecipesAndPhotos() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let store = RecipeStore(folder: library.folder)
        let saved = try store.save(name: "Keep", adjustments: Adjustments())
        let index = library.folder.appending(path: "recipes.json")
        let before = try Data(contentsOf: index)
        #expect(throws: EmulsionError.invalidRecipe) { try store.importRecipe(Data("{}".utf8)) }
        #expect(store.recipes == [saved])
        #expect(try Data(contentsOf: index) == before)
        #expect(library.reopened().photos == [photo])
    }

    @Test func exportedFileCanBeImportedAndBoundedReadsRejectOversize() throws {
        let library = TestLibrary()
        let store = RecipeStore(folder: library.folder)
        let recipe = try #require(CuratedLooks.recipes.last)
        let file = try RecipeTransfer(recipe: recipe).exportFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let imported = try store.importRecipe(at: file)
        #expect(imported.adjustments == recipe.adjustments)
        try Data(repeating: 32, count: Recipe.maximumFileSize + 1).write(to: file)
        #expect(throws: EmulsionError.invalidRecipe) { try store.importRecipe(at: file) }
        #expect(store.recipes == [imported])
    }

    @Test func unreadableCollectionIsNeverOverwritten() throws {
        let library = TestLibrary()
        let index = library.folder.appending(path: "recipes.json")
        try FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        let corrupt = Data("broken saved looks".utf8)
        try corrupt.write(to: index)
        let store = RecipeStore(folder: library.folder)
        #expect(store.loadError == .recipesUnreadable)
        #expect(throws: EmulsionError.recipesUnreadable) { try store.save(name: "New", adjustments: Adjustments()) }
        #expect(try Data(contentsOf: index) == corrupt)
    }

    @Test func unsupportedAndDuplicateCollectionsStayUntouched() throws {
        let library = TestLibrary()
        try FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        let recipe = try #require(CuratedLooks.recipes.first)
        let valid = try JSONEncoder().encode([recipe])
        let future = Data(
            String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2").utf8)
        #expect(future != valid)
        let duplicates = try JSONEncoder().encode([recipe, recipe])
        let index = library.folder.appending(path: "recipes.json")
        for data in [future, duplicates] {
            try data.write(to: index)
            let store = RecipeStore(folder: library.folder)
            #expect(store.loadError == .recipesUnreadable)
            #expect(throws: EmulsionError.recipesUnreadable) { try store.importRecipe(recipe.encoded()) }
            #expect(try Data(contentsOf: index) == data)
        }
    }

    @Test func writeFailureKeepsVisibleAndPersistedLooks() throws {
        let library = TestLibrary()
        let store = RecipeStore(folder: library.folder)
        let saved = try store.save(name: "Keep", adjustments: Adjustments())
        let index = library.folder.appending(path: "recipes.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        #expect(throws: EmulsionError.recipeSaveFailed) { try store.delete(saved) }
        #expect(store.recipes == [saved])
        #expect(throws: EmulsionError.recipeSaveFailed) { try store.save(name: "New", adjustments: Adjustments()) }
        #expect(store.recipes == [saved])
    }

    @Test func applyingKeepsOriginalAndEachPhotosSeed() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let original = try Data(contentsOf: library.store.url(for: photo))
        let session = EditSession(photo: photo, store: library.store)
        for recipe in CuratedLooks.recipes {
            session.apply(recipe)
            #expect(session.adjustments.seed == photo.adjustments.seed)
            #expect(recipe.matches(session.adjustments))
        }
        session.close()
        #expect(library.reopened().photos.first?.adjustments == session.adjustments)
        #expect(try Data(contentsOf: session.url) == original)
        session.reset()
        #expect(session.adjustments == photo.adjustments)
        session.close()
    }
}
