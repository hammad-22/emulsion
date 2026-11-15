import EmulsionCore
import Testing

@testable import EmulsionKit

struct AdjustmentGroupTests {
    @Test func everyEditableValueHasExactlyOneControl() {
        // Every Double the engine reads should have a slider; a new one added to Adjustments fails here until it gets one.
        // Grain size and color are set by the default look and recipes only until their sliders exist (MOV-157).
        let withoutSlider: Set<String> = ["seed", "grainSize", "grainColor"]
        let editable = Mirror(reflecting: Adjustments()).children.filter { $0.value is Double && !withoutSlider.contains($0.label ?? "") }
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
            #expect(control.range(for: .film).contains(defaults[keyPath: control.keyPath]), "\(control.id)")
        }
    }

    @Test(arguments: RenderProcess.allCases)
    func rangesMatchWhatTheEngineClampsTo(process: RenderProcess) {
        for control in AdjustmentGroup.allCases.flatMap({ $0.controls(whiteBalanceAsShot: nil) }) {
            var low = Adjustments()
            low.process = process
            low[keyPath: control.keyPath] = -100
            var high = low
            high[keyPath: control.keyPath] = 100
            #expect(low.clamped()[keyPath: control.keyPath] == control.range(for: process).lowerBound, "\(control.id)")
            #expect(high.clamped()[keyPath: control.keyPath] == control.range(for: process).upperBound, "\(control.id)")
        }
    }

    /// Film grain reaches twice the datasheet granularity; the digicam process's Noise stops at 1 (owner, 14 Nov 2026).
    @Test func filmGrainHasHeadroomAndDigicamNoiseDoesNot() throws {
        let grain = try #require(AdjustmentGroup.texture.controls(whiteBalanceAsShot: nil).first { $0.keyPath == \.grain })
        #expect(grain.range(for: .film) == 0...2)
        #expect(grain.range(for: .digicam) == 0...1)
        #expect(grain.formatted(Adjustments().grain) == "+100")
    }

    /// Reset returns each process to its own default: digicam Noise 0.75, not film grain's 1 (its maximum there).
    @Test func resetDefaultsFollowTheProcess() throws {
        let digicam = Adjustments.defaults(for: .digicam)
        let look = try #require(CuratedLooks.recipes.first { $0.adjustments.process == .digicam }).adjustments
        #expect((digicam.grain, digicam.halation) == (look.grain, look.halation))
        #expect(digicam.grain < Adjustments.grainRange(for: .digicam).upperBound)
        #expect(Adjustments.defaults(for: .film) == Adjustments())
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
        moved[keyPath: control.keyPath] = control.range(for: .film).upperBound
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
        for control in [temperature, tint] { #expect(control.range(for: .film).contains(untouched[keyPath: control.keyPath])) }
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
        #expect(temperature.formatted(temperature.range(for: .film).lowerBound) == "2,000 K")
        #expect(temperature.formatted(temperature.range(for: .film).upperBound) == "50,000 K")
        #expect(temperature.range(for: .film).lowerBound < temperature.range(for: .film).upperBound, "a higher value is a higher kelvin")
        #expect(tint.range(for: .film) == CameraWhiteBalance.tintRange)
        var extreme = Adjustments()
        extreme[keyPath: temperature.keyPath] = temperature.range(for: .film).upperBound
        extreme[keyPath: tint.keyPath] = tint.range(for: .film).lowerBound
        #expect(extreme.clamped() == extreme, "the rulers stay inside what the engine clamps to")
    }

    @Test func theTwoTintsHaveDifferentVoiceOverLabelsAndIdentities() throws {
        let controls = AdjustmentGroup.allCases.flatMap { $0.controls(whiteBalanceAsShot: Self.asShot) }
        for process in RenderProcess.allCases {
            #expect(Set(controls.map { $0.accessibilityLabel(for: process) }).count == controls.count)
        }
        #expect(Set(controls.map(\.id)).count == controls.count)
    }

    /// The digicam process renames two texture controls, for VoiceOver too; ids, key paths and
    /// ranges are shared, so a selection survives switching process.
    @Test func digicamRenamesTheTextureControlsOnly() {
        let controls = AdjustmentGroup.allCases.flatMap { $0.controls(whiteBalanceAsShot: Self.asShot) }
        let renamed = controls.filter { $0.title(for: .digicam) != $0.title(for: .film) }
        #expect(renamed.map(\.id) == ["Grain", "Halation"])
        let texture = AdjustmentGroup.texture.controls(whiteBalanceAsShot: nil)
        #expect(texture.map { $0.title(for: .digicam) } == ["Noise", "Processing"])
        #expect(texture.map { $0.accessibilityLabel(for: .digicam) } == ["Noise", "Processing"])
        #expect(texture.map { $0.title(for: .film) } == ["Grain", "Halation"])
        #expect(texture.map { $0.accessibilityLabel(for: .film) } == ["Grain", "Halation"])
    }
}
