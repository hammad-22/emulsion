import Foundation
import simd

/// Visible steps in a rendered ramp of Display P3 samples (docs/CONSTANTS.md, "Banding").
enum Banding {
    /// About one just-noticeable difference.
    static let minimumVisibleStep = 1.0
    /// Measured: geometric mean of 2.63× (no defect) and 4.2× (MOV-25).
    static let neighbourRatio = 3.3
    static let neighbourhood = 4
    /// Floor on the neighbourhood median, so a flat run doesn't divide by zero.
    static let flatNeighbourhood = 0.05
    /// ΔL* fold limit; measured worst on every ramp −0.010.
    static let largestLightnessDrop = 0.5

    struct Band: Equatable, CustomStringConvertible {
        let index: Int
        let deltaE: Double
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
