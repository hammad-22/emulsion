import EmulsionCore
import Testing

@testable import EmulsionKit

struct AdjustmentGroupTests {
    @Test func everyEditableValueHasExactlyOneControl() {
        // Every Double the engine reads except the seed should have a slider; a new one
        // added to Adjustments fails here until it gets one.
        let editable = Mirror(reflecting: Adjustments()).children.filter { $0.value is Double && $0.label != "seed" }
        let controls = AdjustmentGroup.allCases.flatMap { $0.controls(whiteBalanceAsShot: nil) }
        #expect(controls.count == editable.count)
        #expect(Set(controls.map(\.keyPath)).count == controls.count)
        var probe = Adjustments()
        for (i, control) in controls.enumerated() { probe[keyPath: control.keyPath] = Double(1000 + i) }
        let reached = Mirror(reflecting: probe).children.compactMap { $0.value as? Double }.filter { $0 >= 1000 }
        #expect(reached.count == editable.count, "each control writes a different value")
    }

    @Test func defaultsSitInsideTheirRanges() {
        let defaults = Adjustments()
        for control in AdjustmentGroup.allCases.flatMap({ $0.controls(whiteBalanceAsShot: nil) }) {
            #expect(control.range.contains(defaults[keyPath: control.keyPath]), "\(control.title)")
        }
    }

    @Test func rangesMatchWhatTheEngineClampsTo() {
        for control in AdjustmentGroup.allCases.flatMap({ $0.controls(whiteBalanceAsShot: nil) }) {
            var low = Adjustments()
            low[keyPath: control.keyPath] = -100
            var high = Adjustments()
            high[keyPath: control.keyPath] = 100
            #expect(low.clamped()[keyPath: control.keyPath] == control.range.lowerBound, "\(control.title)")
            #expect(high.clamped()[keyPath: control.keyPath] == control.range.upperBound, "\(control.title)")
        }
    }

    @Test func valuesShowWithSignAndUnit() {
        let exposure = AdjustmentGroup.light.controls(whiteBalanceAsShot: nil)[0]
        #expect(exposure.formatted(0.7) == "+0.7 EV")
        #expect(exposure.formatted(0) == "0.0 EV")
        let warmth = AdjustmentGroup.color.controls(whiteBalanceAsShot: nil)[0]
        #expect(warmth.formatted(-0.35) == "-35")
    }

    /// The last control of each group, so the lookup can't just stop at a group's first.
    @Test(arguments: AdjustmentGroup.allCases)
    func oneMovedRulerIsTheChangedControl(group: AdjustmentGroup) throws {
        let control = try #require(group.controls(whiteBalanceAsShot: Self.asShot).last)
        var moved = Adjustments()
        moved[keyPath: control.keyPath] = control.range.upperBound
        let changed = try #require(AdjustmentGroup.changedControl(from: Adjustments(), to: moved, whiteBalanceAsShot: Self.asShot))
        #expect(changed.group == group)
        #expect(changed.control == control.id)
    }

    @Test func resetAndUnchangedEditsHaveNoSingleChangedControl() {
        var edited = Adjustments()
        edited.exposure = 1
        edited.grain = 0.9
        #expect(AdjustmentGroup.changedControl(from: edited, to: Adjustments(), whiteBalanceAsShot: nil) == nil, "a reset changes several")
        #expect(AdjustmentGroup.changedControl(from: edited, to: edited, whiteBalanceAsShot: nil) == nil)
    }
}

// MARK: White balance rulers (MOV-137)

extension AdjustmentGroupTests {
    static let asShot = CameraWhiteBalance(temperature: 5200, tint: 8)

    private static func whiteBalanceControls() throws -> (temperature: AdjustmentControl, tint: AdjustmentControl) {
        let controls = AdjustmentGroup.whiteBalance.controls(whiteBalanceAsShot: asShot)
        try #require(controls.count == 2)
        return (controls[0], controls[1])
    }

    @Test func onlyAPhotoWithAnAsShotWhiteBalanceHasTheGroup() {
        #expect(AdjustmentGroup.available(whiteBalanceAsShot: nil) == [.light, .color, .texture])
        #expect(AdjustmentGroup.available(whiteBalanceAsShot: Self.asShot) == [.light, .whiteBalance, .color, .texture])
        #expect(AdjustmentGroup.whiteBalance.controls(whiteBalanceAsShot: nil).isEmpty)
    }

    @Test func whiteBalanceRulersRestAtAsShot() throws {
        let (temperature, tint) = try Self.whiteBalanceControls()
        let untouched = Adjustments()
        #expect(temperature.formatted(untouched[keyPath: temperature.keyPath]) == "5,200 K")
        #expect(tint.formatted(untouched[keyPath: tint.keyPath]) == "+8")
        for control in [temperature, tint] { #expect(control.range.contains(untouched[keyPath: control.keyPath])) }
    }

    @Test func movingOneRulerKeepsTheOtherAsShot() throws {
        let (temperature, tint) = try Self.whiteBalanceControls()
        var adjustments = Adjustments()
        adjustments[keyPath: temperature.keyPath] = TemperatureScale.rulerValue(kelvin: 3200)
        let warmer = try #require(adjustments.whiteBalance)
        #expect(abs(warmer.temperature - 3200) < 1e-6)
        #expect(warmer.tint == 8)

        adjustments[keyPath: tint.keyPath] = -20
        #expect(adjustments.whiteBalance?.tint == -20)
        #expect(abs((adjustments.whiteBalance?.temperature ?? 0) - 3200) < 1e-6)
    }

    /// The ruler's detent and Reset write the as-shot value back; so does a drag that stops
    /// within a tenth of a tick of it.
    @Test func backAtAsShotThePhotoIsUnedited() throws {
        let (temperature, tint) = try Self.whiteBalanceControls()
        let asShotValues = (Adjustments()[keyPath: temperature.keyPath], Adjustments()[keyPath: tint.keyPath])
        var adjustments = Adjustments()
        adjustments[keyPath: temperature.keyPath] = TemperatureScale.rulerValue(kelvin: 7000)
        adjustments[keyPath: tint.keyPath] = 30
        adjustments[keyPath: temperature.keyPath] = asShotValues.0 + temperature.increment / 20
        #expect(adjustments.whiteBalance != nil, "the tint is still moved")
        adjustments[keyPath: tint.keyPath] = asShotValues.1 - tint.increment / 20
        #expect(adjustments.whiteBalance == nil)
        #expect(adjustments == Adjustments())

        adjustments[keyPath: tint.keyPath] = asShotValues.1 + tint.increment / 5
        #expect(adjustments.whiteBalance != nil, "a fifth of a tick is a change")
    }

    @Test func temperatureRulerCoversApplesRangeInEqualMiredSteps() throws {
        let (temperature, tint) = try Self.whiteBalanceControls()
        #expect(temperature.formatted(temperature.range.lowerBound) == "2,000 K")
        #expect(temperature.formatted(temperature.range.upperBound) == "50,000 K")
        #expect(temperature.range.lowerBound < temperature.range.upperBound, "a higher value is a higher kelvin")
        #expect(tint.range == CameraWhiteBalance.tintRange)
        var extreme = Adjustments()
        extreme[keyPath: temperature.keyPath] = temperature.range.upperBound
        extreme[keyPath: tint.keyPath] = tint.range.lowerBound
        #expect(extreme.clamped() == extreme, "the rulers stay inside what the engine clamps to")
    }

    @Test func theTwoTintsHaveDifferentVoiceOverLabels() throws {
        let labels = AdjustmentGroup.allCases.flatMap { $0.controls(whiteBalanceAsShot: Self.asShot) }.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }
}
