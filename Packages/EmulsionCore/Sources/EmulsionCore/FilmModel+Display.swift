import Foundation
import simd

/// Display-referred sources (JPEG, HEIC, Rec.709, Display P3); Swift mirror of the
/// `displayToScene` and `filmSystemRelative` kernels. All values are linear Display P3.
///
/// A finished picture has no scene to recover. Its display values get a scene estimate through
/// the film's own neutral print response, with soft ends where the print can't reach (pure white
/// and black). At render time the print's change under the user's edits is applied to the photo
/// itself, so zero edits reproduce it (before the output gamut fit).
extension FilmModel {
    /// Bisection steps of the Swift reference; the kernel takes 22 (3e-6 stops, below float precision).
    private static let referenceSearchSteps = 60

    /// F_n: display-linear green of the calibrated print of a neutral scene `linear`, at zero edits.
    func neutralPrint(_ linear: Double) -> Double { system(SIMD3(repeating: linear), lights: .zero).y }

    /// K, per channel: identity between the knees; above `kneeHigh` display values bend down so
    /// display white lands on F_n(ceiling), below `kneeLow` they bend up so black lands on
    /// F_n(floor). Smooth at the knees, with a closed-form inverse (`expand`).
    struct SoftEnds {
        let kneeHigh, a, kneeLow, b: Double

        init(_ model: FilmModel) {
            let white = model.neutralPrint(0.18 * pow(2, FilmLook.displayCeilingStops))
            let black = model.neutralPrint(0.18 * pow(2, FilmLook.displayFloorStops))
            kneeHigh = FilmLook.displayShoulderKnee
            kneeLow = FilmLook.displayToeKnee
            a = 1 / (white - kneeHigh) - 1 / (1 - kneeHigh)
            b = 1 / (kneeLow - black) - 1 / kneeLow
        }

        func compress(_ y: Double) -> Double {
            if y > kneeHigh { return kneeHigh + (y - kneeHigh) / (1 + a * (y - kneeHigh)) }
            if y < kneeLow { return kneeLow - (kneeLow - y) / (1 + b * (kneeLow - y)) }
            return y
        }

        func expand(_ v: Double) -> Double {
            if v > kneeHigh { return kneeHigh + (v - kneeHigh) / (1 - a * (v - kneeHigh)) }
            if v < kneeLow { return kneeLow - (kneeLow - v) / (1 - b * (kneeLow - v)) }
            return v
        }
    }

    var softEnds: SoftEnds { SoftEnds(self) }

    /// Display-linear P3 → scene estimate: each layer is exposed to the neutral light whose
    /// print matches the soft-ended display value.
    func sceneEstimate(fromDisplay display: SIMD3<Double>) -> SIMD3<Double> {
        let ends = softEnds
        return sensitivity.inverse * SIMD3((0..<3).map { layerExposure(fromDisplay: display[$0], ends: ends) })
    }

    /// One layer's exposure for a display-linear value: the neutral light whose print matches
    /// it after the soft ends, found by bisection.
    func layerExposure(fromDisplay value: Double, ends: SoftEnds) -> Double {
        let target = ends.compress(min(1, max(0, value)))
        var lo = FilmLook.displayFloorStops - FilmLook.displaySearchMarginStops
        var hi = FilmLook.displayCeilingStops + FilmLook.displaySearchMarginStops
        for _ in 0..<Self.referenceSearchSteps {
            let mid = (lo + hi) / 2
            if neutralPrint(0.18 * pow(2, mid)) < target { lo = mid } else { hi = mid }
        }
        return 0.18 * pow(2, (lo + hi) / 2)
    }

    /// The inverse of `sceneEstimate`, in closed form. The neutral print is clamped to what the
    /// soft ends produce for display 0…1, so the result stays in 0…1 for any scene.
    func display(fromSceneEstimate scene: SIMD3<Double>) -> SIMD3<Double> {
        let ends = softEnds
        let (lo, hi) = (ends.compress(0), ends.compress(1))
        let exposure = simd_max(sensitivity * scene, SIMD3(repeating: 1e-7))
        return SIMD3((0..<3).map { ends.expand(min(hi, max(lo, neutralPrint(exposure[$0])))) })
    }

    /// Display-linear print of a display-referred photo under edits, before gamut mapping.
    /// `estimate` is the photo's scene estimate; `edited` is the scene the edits print (the
    /// estimate with exposure and halation applied: `render` does not apply exposure).
    /// Per channel, the edited print's ratio to the zero-edit print is applied to the photo. Where
    /// the photo is darker than its print (gain < 1) and the edit brightens the channel, (1 − gain)²
    /// of the print's increase is added on top, so a zero channel can still rise (desaturation)
    /// and the response has no slope jump at zero edits. `grain` (negative density) enters the
    /// edited print only.
    func renderRelative(
        estimate: SIMD3<Double>, edited: SIMD3<Double>, lights: SIMD3<Double>, saturation: Double, grain: SIMD3<Double> = .zero
    ) -> SIMD3<Double> {
        let base = render(estimate)
        let print = render(edited, lights: lights, saturation: saturation, grain: grain)
        let photo = display(fromSceneEstimate: estimate)
        return SIMD3(
            (0..<3).map { c -> Double in
                let gain = photo[c] / max(base[c], 1e-6)
                let lift = gain < 1 ? (1 - gain) * (1 - gain) * max(print[c] - base[c], 0) : 0
                return print[c] * gain + lift
            })
    }
}
