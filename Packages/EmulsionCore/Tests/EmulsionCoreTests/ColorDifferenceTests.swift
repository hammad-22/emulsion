import EmulsionFixtures
import Testing
import simd

/// The regression suite's colour difference against colour-science and the published
/// CIEDE2000 test data, so the metric that guards every golden is itself checked.
struct ColorDifferenceTests {
    @Test func deltaE2000MatchesPublishedPairs() throws {
        for pair in try ColorReferences.deltaE().labPairs {
            let actual = ColorDifference.deltaE2000(pair.lab1, pair.lab2)
            #expect(abs(actual - pair.deltaE) <= 1e-6, "pair \(pair.pair): \(actual) vs \(pair.deltaE)")
            #expect(ColorDifference.deltaE2000(pair.lab2, pair.lab1) == actual, "pair \(pair.pair) is not symmetric")
        }
    }

    @Test func displayP3ToLabMatchesColourScience() throws {
        for pair in try ColorReferences.deltaE().p3Pairs {
            for (rgb, lab) in [(pair.rgb1, pair.lab1), (pair.rgb2, pair.lab2)] {
                let actual = ColorDifference.lab(fromDisplayP3: rgb)
                #expect(all(simd_abs(actual - lab) .<= SIMD3(repeating: 1e-6)), "\(pair.label) \(rgb): \(actual) vs \(lab)")
            }
        }
    }

    @Test func displayP3DeltaEMatchesColourScience() throws {
        for pair in try ColorReferences.deltaE().p3Pairs {
            let actual = ColorDifference.deltaE2000(displayP3: pair.rgb1, pair.rgb2)
            #expect(abs(actual - pair.deltaE) <= 1e-5, "\(pair.label): \(actual) vs \(pair.deltaE)")
        }
    }

    @Test func summaryUsesNearestRankPercentile() {
        let summary = ColorDifference.Summary((1...20).map(Double.init))
        #expect(summary.count == 20)
        #expect(summary.mean == 10.5)
        #expect(summary.p95 == 19)
        #expect(summary.max == 20)
        #expect(ColorDifference.Summary([0.3]).p95 == 0.3)
        #expect(ColorDifference.Summary((1...100).map(Double.init)).p95 == 95)
        #expect(ColorDifference.Summary((1...21).map(Double.init)).p95 == 20)
        #expect(summary.p999 == 20)
        #expect(ColorDifference.Summary((1...1000).map(Double.init)).p999 == 999)
        #expect(ColorDifference.Summary((1...2001).map(Double.init)).p999 == 1999)
    }

    @Test func chartFixtureMatchesColourScience() throws {
        let reference = try ColorReferences.deltaE().chart24
        try #require(reference.count == SceneFixtures.chart24Patches.count)
        for (patch, expected) in zip(SceneFixtures.chart24Patches, reference) {
            #expect(patch.name == expected.name)
            let actual = SIMD3<Double>(patch.linear)
            #expect(all(simd_abs(actual - expected.linear) .<= SIMD3(repeating: 1e-5)), "\(patch.name): \(actual) vs \(expected.linear)")
        }
    }
}
