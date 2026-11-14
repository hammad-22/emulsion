import Foundation
import simd

/// Finds visible steps (bands) in a rendered smooth ramp: Display P3 encoded samples in the order
/// of a monotone input. A step is a band when it is both visible on its own (`minimumVisibleStep`)
/// and much larger than the steps around it (`neighbourRatio`), which is what the eye picks out as
/// an edge in a gradient. A ramp whose steps are all equally coarse (an 8-bit source lifted by an
/// edit) is quantisation, a known limit of 8-bit sources, not a band; a plateau followed by a jump
/// (contouring) is one, because the plateau's steps are near zero.
enum Banding {
    /// ΔE00 between adjacent samples above which a single step can be seen: about one
    /// just-noticeable difference.
    static let minimumVisibleStep = 1.0
    /// How many times the median of the neighbouring steps a step must be to stand out. Measured
    /// (`BandingTests`): the worst step on `main` and on the −6-stop floor of #50 is 2.63× its
    /// neighbours (blue ramp, shadows +1, codes 0→1); the MOV-25 defect (#50 at a −9-stop floor)
    /// is 4.20× (blue) and 4.24× (gray). 3.3 is about their geometric mean.
    static let neighbourRatio = 3.3
    /// Steps on each side that make up a step's neighbourhood.
    static let neighbourhood = 4
    /// A neighbourhood median below this ΔE00 counts as this, so a flat run (a plateau, or clipped
    /// white) does not divide by zero: a step after it is then judged by `minimumVisibleStep` alone.
    static let flatNeighbourhood = 0.05
    /// A lightness drop (ΔL*) larger than this on a rising ramp is a fold, reported as a band.
    /// Measured worst on every ramp: −0.010.
    static let largestLightnessDrop = 0.5

    struct Band: Equatable, CustomStringConvertible {
        /// The step is from sample `index` to `index + 1`.
        let index: Int
        let deltaE: Double
        /// `deltaE` over the neighbourhood median.
        let ratio: Double
        let lightnessChange: Double

        var description: String {
            String(format: "step %d→%d: ΔE00 %.2f, %.2f× neighbours, ΔL* %+.2f", index, index + 1, deltaE, ratio, lightnessChange)
        }
    }

    struct Profile {
        /// ΔE00 from each sample to the next.
        let steps: [Double]
        /// ΔL* from each sample to the next.
        let lightnessChanges: [Double]

        init(_ samples: [SIMD3<Double>]) {
            let lab = samples.map(ColorDifference.lab(fromDisplayP3:))
            let pairs = zip(lab, lab.dropFirst())
            steps = pairs.map { ColorDifference.deltaE2000($0, $1) }
            lightnessChanges = pairs.map { $1.x - $0.x }
        }

        /// Each step over the median of up to `neighbourhood` steps on either side.
        var ratios: [Double] {
            steps.indices.map { i in
                let window = max(0, i - Banding.neighbourhood)...min(steps.count - 1, i + Banding.neighbourhood)
                let neighbours = window.filter { $0 != i }.map { steps[$0] }.sorted()
                guard !neighbours.isEmpty else { return 1 }
                return steps[i] / max(neighbours[neighbours.count / 2], Banding.flatNeighbourhood)
            }
        }

        var bands: [Band] {
            zip(steps.indices, ratios).compactMap { i, ratio in
                let stands = steps[i] > Banding.minimumVisibleStep && ratio > Banding.neighbourRatio
                let folds = lightnessChanges[i] < -Banding.largestLightnessDrop
                return stands || folds ? Band(index: i, deltaE: steps[i], ratio: ratio, lightnessChange: lightnessChanges[i]) : nil
            }
        }
    }

    static func bands(in samples: [SIMD3<Double>]) -> [Band] { Profile(samples).bands }
}
