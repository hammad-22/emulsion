import EmulsionFixtures
import Testing
import simd

@testable import EmulsionCore

/// The input transforms against colour-science, with chromatic samples so a wrong gamut
/// matrix can't hide behind gray.
struct ColorReferenceTests {
    @Test(arguments: InputColorSpace.allCases)
    func swiftMirrorMatchesColourScience(space: InputColorSpace) throws {
        for sample in try ColorReferences.samples(for: space) {
            let decoded = sample.code.decoded(curve: space.curve)
            withHLGSubBlackKnownIssue(space, sample) {
                ColorReferences.expectMatch(space.toWorking * decoded, sample.working, ColorReferences.mirrorTolerance, sample.label)
            }
        }
    }

    /// Scene-referred encodings are compared directly. Display encodings leave the developer as
    /// scene light through the inverse film curve, so the reference goes through the same
    /// `sceneFromDisplay` step: the decode under test still runs on the GPU from code values.
    @Test(arguments: InputColorSpace.allCases)
    func kernelMatchesColourScience(space: InputColorSpace) throws {
        let samples = try ColorReferences.samples(for: space)
        let developer = EmulsionTestCase.sharedRenderer.developer
        let output = Fixtures.linear(try developer.scene(fromEncoded: ColorReferences.encodedImage(samples), as: space).image)
        var expected = samples.map(\.working)
        if space.isDisplayReferred {
            let reference = Fixtures.row(expected.map { SIMD3<Float>($0) }, space: Fixtures.linearSRGB)
            expected = Fixtures.linear(try developer.sceneFromDisplay(reference).image)
        }
        try #require(output.count == samples.count)
        for (sample, (actual, expected)) in zip(samples, zip(output, expected)) {
            withHLGSubBlackKnownIssue(space, sample) {
                ColorReferences.expectMatch(actual, expected, ColorReferences.kernelTolerance, sample.label)
            }
        }
    }

    /// MOV-125: HLG squares sub-black signals into positive light; colour-science mirrors them.
    /// Remove this once the decode is fixed (the known issue then fails for not occurring).
    private func withHLGSubBlackKnownIssue(_ space: InputColorSpace, _ sample: ColorReferences.Sample, _ body: () -> Void) {
        guard space == .hlgRec2020, simd_reduce_min(sample.code) < 0 else { return body() }
        withKnownIssue("MOV-125: HLG sub-black signals decode to positive light", body)
    }
}

extension SIMD3<Double> {
    fileprivate func decoded(curve: Int) -> Self {
        Self(ColorMath.decode(x, curve: curve), ColorMath.decode(y, curve: curve), ColorMath.decode(z, curve: curve))
    }
}
