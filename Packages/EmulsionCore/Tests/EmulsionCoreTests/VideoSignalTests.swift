import AVFoundation
import CoreImage
import EmulsionFixtures
import Testing
import simd

@testable import EmulsionCore

/// One fixture movie: every patch of one input, written with one codec in one range.
struct VideoFixtureCase: CustomTestStringConvertible, Sendable {
    let space: InputColorSpace
    let codec: VideoFixtures.Codec
    let range: SignalRange

    let references: [ColorReferences.VideoSample]

    init(space: InputColorSpace, codec: VideoFixtures.Codec, range: SignalRange) {
        (self.space, self.codec, self.range) = (space, codec, range)
        // The table is checked into the test bundle; a load failure fails the reference tests.
        let samples = (try? ColorReferences.videoSamples()) ?? []
        references = samples.filter { $0.space == space && $0.signal.range == range }
    }

    var testDescription: String { "\(space.title) \(codec) \(range)" }

    static let spaces: [InputColorSpace] = [.sLog3SGamut3Cine, .arriLogC3, .vLog, .appleLog, .hlgRec2020]
    /// ProRes has no full-range coding, so it is tested in legal range only.
    static let all = spaces.flatMap { space in
        [(VideoFixtures.Codec.hevcMain10, SignalRange.legal), (.hevcMain10, .full), (.proRes422HQ, .legal)]
            .map { VideoFixtureCase(space: space, codec: $0, range: $1) }
    }

    func movieFrame() async throws -> CVPixelBuffer {
        let tag = references[0].signal.matrix == .bt2020 ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2
        return try await VideoFixtures.roundTrip(
            references.map { SIMD3(truncatingIfNeeded: $0.code) }, codec: codec, fullRange: range == .full, matrixTag: tag)
    }
}

/// Serialized: AVAssetReader blocks its thread while decoding, and many parallel readers starve
/// the Swift concurrency pool (observed deadlock).
@Suite(.serialized)
struct VideoSignalTests {
    /// Whether every channel is within `tolerance`, relative above 1.0 (used to show that a wrong
    /// assumption misses by far more than the reference tolerance).
    static func matches(_ value: SIMD3<Double>, _ reference: SIMD3<Double>, tolerance: Double = 1e-3) -> Bool {
        (0..<3).allSatisfy { abs(value[$0] - reference[$0]) <= tolerance * max(1, abs(reference[$0])) }
    }

    /// Decoded scene light at each patch center of a fixture frame.
    static func decodedPatches(_ frame: CVPixelBuffer, as space: InputColorSpace, signal: VideoSignal? = nil) throws -> [SIMD3<Double>] {
        let scene = try EmulsionTestCase.sharedRenderer.developer.scene(fromYCbCr: frame, as: space, signal: signal)
        let pixels = Fixtures.linear(scene.image)
        let width = Int(scene.size.width)
        return (0..<width / VideoFixtures.patchSize).map {
            let (x, y) = VideoFixtures.center(ofPatch: $0)
            return pixels[y * width + x]
        }
    }

    @Test("The Swift mirror decodes every reference patch")
    func mirrorMatchesColourScience() throws {
        let samples = try ColorReferences.videoSamples()
        try #require(samples.count == VideoFixtureCase.spaces.count * 2 * 3)
        for sample in samples {
            let transform = CurveInputTransform(ycbcrIn: sample.signal, sampleUnitsPerCode: 1, for: sample.space)
            let curveInput = transform.apply(SIMD3(sample.code))
            let camera = SIMD3(curveInput.indices.map { ColorMath.decode(curveInput[$0], curve: sample.space.curve) })
            ColorReferences.expectMatch(
                sample.space.toWorking * camera, sample.working, ColorReferences.mirrorTolerance, sample.testDescription)
        }
    }

    @Test("10-bit HEVC and ProRes frames decode to the colour-science references", arguments: VideoFixtureCase.all)
    func fixtureDecodesReferences(_ fixture: VideoFixtureCase) async throws {
        let frame = try await fixture.movieFrame()
        // The range comes from the pixel format and the matrix from the file's tag, not the fallback.
        let layout = try #require(YCbCrLayout(frame))
        let signal = VideoSignal(frame: frame, layout: layout, fallbackMatrix: fixture.references[0].signal.matrix.other)
        #expect(signal == fixture.references[0].signal)
        for (decoded, reference) in zip(try Self.decodedPatches(frame, as: fixture.space), fixture.references) {
            ColorReferences.expectMatch(decoded, reference.working, ColorReferences.kernelTolerance, reference.testDescription)
        }
    }

    /// An independent check of the range and matrix conventions: Core Image's own Y′CbCr → R′G′B′
    /// conversion of the same frame (no color matching) must agree with ours. Decoded as linear
    /// Display P3 (identity curve), so the comparison is on the signal itself. Measured: legal range
    /// agrees within 1e-5; in full range Core Image's chroma is ~0.1% wider than BT.2100's
    /// (D − 512) / 1023 (2e-4 of signal on the chromatic patch). Emulsion follows BT.2100, as
    /// colour-science does.
    @Test(
        "Y′CbCr conversion agrees with Core Image's own",
        arguments: VideoFixtureCase.all.filter { $0.space == .appleLog || $0.space == .sLog3SGamut3Cine })
    func conversionMatchesCoreImage(_ fixture: VideoFixtureCase) async throws {
        let frame = try await fixture.movieFrame()
        let ours = try Self.decodedPatches(frame, as: .linearP3)
        let coreImage = Fixtures.linear(CIImage(cvPixelBuffer: frame, options: [.colorSpace: NSNull()]))
        let width = CVPixelBufferGetWidth(frame)
        for (i, decoded) in ours.enumerated() {
            let (x, y) = VideoFixtures.center(ofPatch: i)
            let expected = InputColorSpace.linearP3.toWorking * coreImage[y * width + x]
            let tolerance = fixture.range == .legal ? 1e-5 : 3e-4
            #expect(Self.matches(decoded, expected, tolerance: tolerance), "patch \(i): \(decoded) vs \(expected)")
        }
    }

    @Test("A wrong range or matrix assumption misses the references", arguments: VideoFixtureCase.spaces)
    func wrongAssumptionFails(_ space: InputColorSpace) async throws {
        let fixture = VideoFixtureCase(space: space, codec: .hevcMain10, range: .legal)
        let frame = try await fixture.movieFrame()
        let right = fixture.references[0].signal
        let wrongRange = VideoSignal(range: .full, matrix: right.matrix)
        let wrongMatrix = VideoSignal(range: right.range, matrix: right.matrix.other)
        let references = fixture.references.map(\.working)
        // Legal and full coding agree at code 446 (64 + 876·E′ = 1023·E′), so gray patches near it
        // barely move; white (codes 572–721) lands 20+ codes off, far outside the tolerance.
        let white = try Self.decodedPatches(frame, as: space, signal: wrongRange)[1]
        #expect(!Self.matches(white, references[1], tolerance: 1e-2), "\(white)")
        // Neutral patches don't depend on the matrix; the chromatic one does.
        let chroma = try Self.decodedPatches(frame, as: space, signal: wrongMatrix)[2]
        #expect(!Self.matches(chroma, references[2], tolerance: 1e-2), "\(chroma)")
    }
}

extension YCbCrMatrix {
    /// The matrix a mistagged file would be read with.
    var other: YCbCrMatrix { self == .bt709 ? .bt2020 : .bt709 }
}
