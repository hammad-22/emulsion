import EmulsionCore
import Testing

@testable import EmulsionKit

struct AdjustmentGroupTests {
    @Test func everyEditableValueHasExactlyOneControl() {
        // Every Double the engine reads except the seed should have a slider; a new one
        // added to Adjustments fails here until it gets one.
        let editable = Mirror(reflecting: Adjustments()).children.filter { $0.value is Double && $0.label != "seed" }
        let controls = AdjustmentGroup.allCases.flatMap { $0.controls(for: .film) }
        #expect(controls.count == editable.count)
        #expect(Set(controls.map(\.keyPath)).count == controls.count)
        var probe = Adjustments()
        for (i, control) in controls.enumerated() { probe[keyPath: control.keyPath] = Double(1000 + i) }
        let reached = Mirror(reflecting: probe).children.compactMap { $0.value as? Double }.filter { $0 >= 1000 }
        #expect(reached.count == editable.count, "each control writes a different value")
    }

    @Test func defaultsSitInsideTheirRanges() {
        let defaults = Adjustments()
        for control in AdjustmentGroup.allCases.flatMap { $0.controls(for: .film) } {
            #expect(control.range.contains(defaults[keyPath: control.keyPath]), "\(control.title)")
        }
    }

    @Test func rangesMatchWhatTheEngineClampsTo() {
        for control in AdjustmentGroup.allCases.flatMap { $0.controls(for: .film) } {
            var low = Adjustments()
            low[keyPath: control.keyPath] = -100
            var high = Adjustments()
            high[keyPath: control.keyPath] = 100
            #expect(low.clamped()[keyPath: control.keyPath] == control.range.lowerBound, "\(control.title)")
            #expect(high.clamped()[keyPath: control.keyPath] == control.range.upperBound, "\(control.title)")
        }
    }

    @Test func valuesShowWithSignAndUnit() {
        let exposure = AdjustmentGroup.light.controls(for: .film)[0]
        #expect(exposure.formatted(0.7) == "+0.7 EV")
        #expect(exposure.formatted(0) == "0.0 EV")
        let warmth = AdjustmentGroup.color.controls(for: .film)[0]
        #expect(warmth.formatted(-0.35) == "-35")
    }

    /// The last control of each group, so the lookup can't just stop at a group's first.
    @Test(arguments: AdjustmentGroup.allCases)
    func oneMovedRulerIsTheChangedControl(group: AdjustmentGroup) throws {
        let control = try #require(group.controls(for: .film).last)
        var moved = Adjustments()
        moved[keyPath: control.keyPath] = control.range.upperBound
        let changed = try #require(AdjustmentGroup.changedControl(from: Adjustments(), to: moved))
        #expect(changed.group == group)
        #expect(changed.control == control.id)
    }

    @Test func resetAndUnchangedEditsHaveNoSingleChangedControl() {
        var edited = Adjustments()
        edited.exposure = 1
        edited.grain = 0.9
        #expect(AdjustmentGroup.changedControl(from: edited, to: Adjustments()) == nil, "a reset changes several")
        #expect(AdjustmentGroup.changedControl(from: edited, to: edited) == nil)
    }

    /// The digicam process renames two texture controls; the ids, key paths and ranges stay, so
    /// a selection survives switching process.
    @Test func digicamRenamesTheTextureControlsOnly() {
        for group in AdjustmentGroup.allCases {
            let film = group.controls(for: .film)
            let digicam = group.controls(for: .digicam)
            #expect(film.map(\.id) == digicam.map(\.id))
            #expect(film.map(\.keyPath) == digicam.map(\.keyPath))
            #expect(film.map(\.range) == digicam.map(\.range))
        }
        #expect(AdjustmentGroup.texture.controls(for: .digicam).map(\.title) == ["Noise", "Processing"])
        #expect(AdjustmentGroup.texture.controls(for: .film).map(\.title) == ["Grain", "Halation"])
        #expect(AdjustmentGroup.light.controls(for: .digicam).map(\.title) == AdjustmentGroup.light.controls(for: .film).map(\.title))
    }
}
