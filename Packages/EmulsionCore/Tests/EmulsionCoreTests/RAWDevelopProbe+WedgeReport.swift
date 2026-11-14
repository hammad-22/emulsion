import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

extension RAWDevelopProbe {
    /// Probe labels only: a clipped patch within 2 % of neutral prints as "neutral", and a patch
    /// counts as still rising when it is over 1 % brighter than the one below it.
    static let neutralLabelLimit = 0.02
    static let risingRatio = 1.01

    /// SUMMARY lines for a developed wedge; `rows` adds a line per patch.
    static func report(_ out: Readout, chart: PatchChart, cameras: [SIMD3<Double>], scale: Double, rows: Bool) {
        let means = Self.means(out, chart: chart)
        print(
            "  extent=\(out.extent) render=\(out.milliseconds.fourDigits) ms max=\(RAWDevelopSupport.maxValue(out.pixels).fourDigits) NaN pixels=\(out.nanCount)"
        )
        if rows {
            print("  patch expected                          measured                        G ratio   R/G      B/G      sensor")
            for i in means.indices {
                let expected = chart.patches[i] * scale
                let m = means[i]
                print(
                    "  \(pad(String(i), 5)) \(pad(expected.fourDigits, 32)) \(pad(m.fourDigits, 31)) \(pad((m.y / expected.y).fourDigits, 9))"
                        + " \(pad((m.x / m.y).fourDigits, 8)) \(pad((m.z / m.y).fourDigits, 8)) \(cameras[i].max() > 1 ? "clipped" : "")"
                )
            }
        }
        let neutral = Array(RAWDevelopChart.neutralIndices)
        let unclipped = neutral.filter { cameras[$0].max() < 1 && means[$0].y > 1e-4 }
        let clipped = neutral.filter { cameras[$0].max() >= 1 }
        let midIndex = RAWDevelopChart.wedgeStops.firstIndex(of: 0) ?? 0
        let midRatio = means[midIndex].y / (chart.patches[midIndex].y * scale)
        func slope(_ indices: [Int]) -> String {
            guard indices.count >= 2 else { return "n/a" }
            let xs = indices.map { log2(chart.patches[$0].y * scale) }
            let ys = indices.map { log2(means[$0].y) }
            let mx = xs.reduce(0, +) / Double(xs.count)
            let my = ys.reduce(0, +) / Double(ys.count)
            let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
            return (num / xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)).fourDigits
        }
        let below = unclipped.filter { chart.patches[$0].y * scale < 1 }
        let above = unclipped.filter { chart.patches[$0].y * scale >= 1 }
        let deviation = unclipped.map { abs(means[$0].y / (chart.patches[$0].y * scale) / midRatio - 1) }.max() ?? .nan
        let neutralError = unclipped.map { RAWDevelopSupport.neutralError(means[$0]) }.max() ?? .nan
        var lastRising = neutral.first ?? 0
        for i in neutral.dropFirst() where means[i].y > means[i - 1].y * risingRatio { lastRising = i }
        print(
            "  SUMMARY scale@0.18 (measured/expected G)=\(midRatio.fourDigits) log-log slope expected<1 \(slope(below)) [n=\(below.count)]"
                + " expected>=1 \(slope(above)) [n=\(above.count)] max |ratio/ratio@0.18-1| unclipped=\(deviation.fourDigits)")
        print(
            "  SUMMARY highest neutral G=\((neutral.map { means[$0].y }.max() ?? .nan).fourDigits) last patch still rising >1%: #\(lastRising)"
                + " (expected \((chart.patches[lastRising].y * scale).fourDigits)) neutral error unclipped max(|R/G-1|,|B/G-1|)=\(neutralError.fourDigits)"
        )
        for i in clipped {
            let m = means[i]
            let tint = RAWDevelopSupport.neutralError(m) < neutralLabelLimit ? "neutral" : "tinted"
            print(
                "  SUMMARY clipped #\(i) expected \((chart.patches[i].y * scale).fourDigits) measured \(m.fourDigits)"
                    + " R/G=\((m.x / m.y).fourDigits) B/G=\((m.z / m.y).fourDigits) \(tint)")
        }
        for i in RAWDevelopChart.outOfSRGBIndices {
            let expected = chart.patches[i] * scale
            print(
                "  SUMMARY out-of-sRGB #\(i) expected \(expected.fourDigits) measured \(means[i].fourDigits)"
                    + " min component expected \(expected.min().fourDigits) measured \(means[i].min().fourDigits)")
        }
    }
}
