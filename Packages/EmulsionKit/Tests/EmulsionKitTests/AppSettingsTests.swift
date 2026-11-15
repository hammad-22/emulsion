import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct AppSettingsTests {
    @Test func cameraRecipeReadsBackWholeOnceNoSavedLookHasIt() throws {
        let library = TestLibrary()
        #expect(library.settings.recipe == CuratedLooks.recipes.first, "Everyday until one is chosen")

        let saved = try Recipe(name: "Saved Look", adjustments: TestLooks.curated(3).adjustments)
        library.settings.recipe = saved

        #expect(library.reopenedSettings().recipe == saved)
    }

    @Test func unreadableCameraRecipeFallsBackToEveryday() throws {
        let library = TestLibrary()
        library.settingsDefaults.set(Data("not a recipe".utf8), forKey: "cameraRecipe")

        #expect(library.reopenedSettings().recipe == CuratedLooks.recipes.first)
    }
}
