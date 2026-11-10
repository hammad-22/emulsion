import EmulsionCore
import Foundation
import Testing

/// Edits are stored in every user's library index, so decoding must survive app updates.
struct AdjustmentsCodingTests {
    @Test func missingFieldsKeepTheirDefaults() throws {
        let saved = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"exposure": 1.5}"#.utf8))
        var expected = Adjustments()
        expected.exposure = 1.5
        #expect(saved == expected)
    }

    @Test func everyFieldRoundTrips() throws {
        let edited = Adjustments.everyFieldEdited
        #expect(Mirror(reflecting: edited).children.count == 9, "a new field needs a line in init(from:) and here")
        #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(edited)) == edited)
    }
}

extension Adjustments {
    /// Every field away from its default, so a field the decoder skips shows up.
    fileprivate static var everyFieldEdited: Adjustments {
        var a = Adjustments()
        a.exposure = 1
        a.warmth = 0.1
        a.tint = 0.2
        a.color = 0.3
        a.highlights = 0.4
        a.shadows = 0.5
        a.grain = 0.6
        a.halation = 0.7
        a.seed = 8
        return a
    }
}
