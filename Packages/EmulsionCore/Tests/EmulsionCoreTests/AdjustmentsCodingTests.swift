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

    /// A library saved before RAW white balance existed (MOV-10) develops as shot.
    @Test func editsWithoutAWhiteBalanceDevelopAsShot() throws {
        let saved = try JSONDecoder().decode(
            Adjustments.self, from: Data(#"{"exposure": 0.5, "warmth": 0.2, "grain": 0.1, "seed": 3}"#.utf8))
        #expect(saved.whiteBalance == nil)
        #expect(Adjustments.neutral.whiteBalance == nil)
        #expect(Adjustments().whiteBalance == nil)
    }

    /// Edits saved before the backing existed (MOV-32) keep the default rem-jet backing.
    @Test func editsWithoutABackingUseRemJet() throws {
        let saved = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"halation": 0.5}"#.utf8))
        #expect(saved.backing == .remJet)
        var unbacked = Adjustments()
        unbacked.backing = .unbacked
        #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(unbacked)).backing == .unbacked)
    }

    @Test func everyFieldRoundTrips() throws {
        let edited = Adjustments.everyFieldEdited
        #expect(Mirror(reflecting: edited).children.count == 11, "a new field needs a line in init(from:) and here")
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
        a.backing = .undercoat
        a.seed = 8
        a.whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 9)
        return a
    }
}
