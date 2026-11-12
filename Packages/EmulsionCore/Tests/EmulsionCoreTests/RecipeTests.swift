import Foundation
import Testing

@testable import EmulsionCore

struct RecipeTests {
    @Test func roundTripExcludesPhotoSeed() throws {
        var settings = Adjustments()
        settings.warmth = 0.4
        settings.tint = -0.2
        settings.exposure = 1.2
        settings.seed = 999
        let recipe = try Recipe(name: "Evening", adjustments: settings)
        let data = try recipe.encoded()
        #expect(try Recipe.decode(data) == recipe)
        #expect(!String(decoding: data, as: UTF8.self).contains("seed"))
        #expect(recipe.applying(to: settings) == settings)
        settings.seed = 123
        #expect(recipe.applying(to: settings).seed == 123)
    }

    /// White balance describes the light one photo was shot under, so a recipe neither stores it
    /// nor changes it.
    @Test func photoKeepsItsWhiteBalance() throws {
        var settings = Adjustments()
        settings.warmth = 0.3
        settings.whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 5)
        let recipe = try Recipe(name: "Tungsten", adjustments: settings)
        #expect(recipe.adjustments.whiteBalance == nil)
        #expect(try Recipe.decode(recipe.encoded()) == recipe)
        var photo = Adjustments()
        photo.whiteBalance = CameraWhiteBalance(temperature: 5600, tint: -4)
        let applied = recipe.applying(to: photo)
        #expect(applied.whiteBalance == photo.whiteBalance)
        #expect(applied.warmth == 0.3)
        #expect(recipe.matches(applied))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 3.01, -3.01])
    func rejectsInvalidExposure(_ value: Double) {
        var settings = Adjustments()
        settings.exposure = value
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "Invalid", adjustments: settings) }
    }

    @Test func rejectsInvalidNamesAndEveryAdjustmentRange() throws {
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "  ", adjustments: Adjustments()) }
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "Bad\nName", adjustments: Adjustments()) }
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: String(repeating: "a", count: 81), adjustments: Adjustments()) }
        let paths: [WritableKeyPath<Adjustments, Double>] = [\.warmth, \.tint, \.color, \.highlights, \.shadows, \.grain, \.halation]
        for path in paths {
            for value in [Double.nan, .infinity, -.infinity, -1.01, 1.01] {
                var settings = Adjustments()
                settings[keyPath: path] = value
                #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "Bad", adjustments: settings) }
            }
        }
        for path in [\Adjustments.grain, \.halation] {
            var settings = Adjustments()
            settings[keyPath: path] = -0.01
            #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "Bad", adjustments: settings) }
        }
    }

    @Test func savedMetadataAlwaysFitsTheShareableFormat() {
        let oversizedGrapheme = "a" + String(repeating: "\u{0301}", count: Recipe.maximumFileSize)
        #expect(oversizedGrapheme.count == 1)
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: oversizedGrapheme, adjustments: Adjustments()) }
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe(name: "Test", summary: oversizedGrapheme, adjustments: Adjustments()) }
    }

    @Test func curatedLooksAreValidDistinctAndSeedIndependent() throws {
        #expect(CuratedLooks.recipes.count == 4)
        #expect(Set(CuratedLooks.recipes.map(\.id)).count == 4)
        for recipe in CuratedLooks.recipes {
            #expect(try Recipe.decode(recipe.encoded()) == recipe)
            var settings = Adjustments()
            settings.seed = 817
            #expect(recipe.applying(to: settings).seed == 817)
        }
    }

    /// Format 2 stores the backing beside the numeric adjustments, in one `adjustments` object, and
    /// requires it; an unknown backing is rejected.
    @Test func formatTwoRequiresTheBacking() throws {
        var unbacked = Adjustments()
        unbacked.backing = .unbacked
        let data = try Recipe(name: "Glow", adjustments: unbacked).encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["formatVersion"] as? Int == 2)
        let settings = try #require(object["adjustments"] as? [String: Any])
        #expect(settings.count == 9 && settings["backing"] as? String == "none")
        #expect(try Recipe.decode(data).adjustments.backing == .unbacked)
        let json = String(decoding: data, as: UTF8.self)
        let withoutBacking = json.replacingOccurrences(of: "\"backing\" : \"none\",", with: "")
        #expect(withoutBacking != json)
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe.decode(Data(withoutBacking.utf8)) }
        let unknown = json.replacingOccurrences(of: "\"backing\" : \"none\"", with: "\"backing\" : \"felt\"")
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe.decode(Data(unknown.utf8)) }
    }

    /// Format 1 has no backing and prints with rem-jet. A `backing` key in a format-1 file is an
    /// unknown key: ignored, as every format-1 reader ignores it, so it cannot change rendering
    /// without a version change (docs/RECIPES.md).
    @Test func formatOneReadsAsRemJetAndIgnoresABacking() throws {
        var unbacked = Adjustments()
        unbacked.backing = .unbacked
        let json = String(decoding: try Recipe(name: "Glow", adjustments: unbacked).encoded(), as: UTF8.self)
        let formatOne = json.replacingOccurrences(of: "\"formatVersion\" : 2", with: "\"formatVersion\" : 1")
        #expect(formatOne != json)
        #expect(try Recipe.decode(Data(formatOne.utf8)).adjustments.backing == .remJet)
        let withoutBacking = formatOne.replacingOccurrences(of: "\"backing\" : \"none\",", with: "")
        #expect(withoutBacking != formatOne)
        #expect(try Recipe.decode(Data(withoutBacking.utf8)).adjustments.backing == .remJet)
    }

    /// MOV-92: no film brand or stock names in the product.
    @Test func curatedLooksNameNoFilmBrandOrStock() {
        let banned = [
            "kodak", "fuji", "portra", "ektar", "velvia", "provia", "cinestill", "ilford", "agfa", "tri-x", "gold", "superia",
            "vision3",
        ]
        for recipe in CuratedLooks.recipes {
            let text = (recipe.name + " " + recipe.summary).lowercased()
            #expect(!banned.contains { text.contains($0) }, "\(recipe.name)")
        }
    }

    @Test func compatibilityAndCorruptionAreExplicit() throws {
        let data = try Recipe(name: "Test", adjustments: Adjustments()).encoded()
        let json = String(decoding: data, as: UTF8.self)
        for version in [0, 3] {
            let changed = Data(json.replacingOccurrences(of: "\"formatVersion\" : 2", with: "\"formatVersion\" : \(version)").utf8)
            #expect(throws: EmulsionError.recipeVersionUnsupported) { try Recipe.decode(changed) }
            #expect(throws: EmulsionError.recipeVersionUnsupported) { try JSONDecoder().decode(Recipe.self, from: changed) }
        }
        #expect(throws: EmulsionError.recipeModelUnsupported) {
            try Recipe.decode(Data(json.replacingOccurrences(of: Recipe.engineModel, with: "future-model").utf8))
        }
        for invalid in [
            "{}", "[]", "not json", json.replacingOccurrences(of: "\"grain\" : 0.35,", with: ""),
            json.replacingOccurrences(of: "\"grain\" : 0.35", with: "\"grain\" : -1"),
        ] {
            #expect(throws: EmulsionError.invalidRecipe) { try Recipe.decode(Data(invalid.utf8)) }
        }
        #expect(throws: EmulsionError.invalidRecipe) { try Recipe.decode(Data(repeating: 32, count: Recipe.maximumFileSize + 1)) }
    }
}
