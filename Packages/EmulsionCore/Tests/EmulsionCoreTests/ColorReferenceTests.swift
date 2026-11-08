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
            ColorReferences.expectMatch(space.toWorking * decoded, sample.working, ColorReferences.mirrorTolerance, sample.label)
        }
    }

    /// The GPU input transform (curve and gamut matrix, before display encodings' inverse film
    /// curve), including display negatives and superwhite. Each sample's code is its formula's own
    /// input, so it is decoded in `formulaRange`.
    @Test(arguments: InputColorSpace.allCases)
    func kernelMatchesColourScience(space: InputColorSpace) throws {
        let samples = try ColorReferences.samples(for: space)
        try expectKernelMatches(samples, codes: samples.map(\.code), in: space.formulaRange, as: space)
    }

    /// The same samples re-coded into the other signal range decode to the same light (MOV-80).
    @Test(arguments: InputColorSpace.allCases)
    func kernelMatchesColourScienceInTheOtherRange(space: InputColorSpace) throws {
        let samples = try ColorReferences.samples(for: space)
        let native = space.formulaRange
        let other: SignalRange = native == .legal ? .full : .legal
        let codes = samples.map { (($0.code * 1023 - native.lumaBlack) / native.lumaSpan * other.lumaSpan + other.lumaBlack) / 1023 }
        try expectKernelMatches(samples, codes: codes, in: other, as: space)
    }

    private func expectKernelMatches(
        _ samples: [ColorReferences.Sample], codes: [SIMD3<Double>], in range: SignalRange, as space: InputColorSpace
    ) throws {
        let image = Fixtures.row(codes.map { SIMD3<Float>($0) }, space: nil)
        let developer = EmulsionTestCase.sharedRenderer.developer
        let output = Fixtures.linear(try developer.workingLight(fromEncoded: image, as: space, range: range))
        try #require(output.count == samples.count)
        for (sample, actual) in zip(samples, output) {
            ColorReferences.expectMatch(actual, sample.working, ColorReferences.kernelTolerance, "\(range) \(sample.label)")
        }
    }

    @Test func referenceTableCoversExactlyTheInputColorSpaces() throws {
        #expect(try ColorReferences.spaceNames() == Set(InputColorSpace.allCases.map(\.rawValue)))
    }
}

extension SIMD3<Double> {
    fileprivate func decoded(curve: Int) -> Self {
        Self(ColorMath.decode(x, curve: curve), ColorMath.decode(y, curve: curve), ColorMath.decode(z, curve: curve))
    }
}
