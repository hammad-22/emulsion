import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// A RAW decoder kept alive for interactive white balance (MOV-137) develops exactly what a
/// develop from the file does, at every white balance and back to as shot.
struct RAWDecoderTests {
    static var developer: Developer { EmulsionTestCase.sharedRenderer.developer }

    /// A tungsten-lit chart tagged as daylight, with a gain table so the develop measures an anchor.
    static func file(_ mosaic: SyntheticDNG.Mosaic) -> Data {
        RAWDevelopChart.dng(
            mosaic, chart: CameraWhiteBalanceTests.chart, light: CameraWhiteBalanceTests.tungsten,
            taggedLight: CameraWhiteBalanceTests.d65, baselineStops: 0.5, profile: SyntheticDNG.Profile(gainTableGain: 4))
    }

    static let tungsten = CameraWhiteBalance(temperature: CameraWhiteBalanceTests.tungstenKelvin, tint: 0)
    static let whiteBalances: [CameraWhiteBalance?] = [
        nil, tungsten, CameraWhiteBalance(temperature: 4200, tint: 25), CameraWhiteBalance(temperature: 9000, tint: -40), nil,
    ]

    /// Largest channel difference between two renders of the same size.
    static func worstDifference(_ a: CIImage, _ b: CIImage) -> Double {
        zip(Fixtures.linear(a), Fixtures.linear(b)).map { abs($0 - $1).max() }.max() ?? .nan
    }

    /// Back at as shot after another white balance, against the file's own untouched neutral:
    /// measured 6.0e-7 on the linear file and 9.5e-7 on the Bayer one (about 2× the worst).
    static let backToAsShotTolerance = 2e-6

    /// `Developer.develop` is itself one `negative` of a decoder, so the reference for as shot
    /// is a `CIRAWFilter` nothing has set a neutral on.
    @Test(arguments: SyntheticDNG.Mosaic.allCases)
    func asShotIsTheUntouchedFilesNeutral(mosaic: SyntheticDNG.Mosaic) throws {
        let data = Self.file(mosaic)
        let untouched = try #require(CIRAWFilter(imageData: data, identifierHint: Developer.dngTypeIdentifier))
        Developer.bypassAppleRendering(untouched)
        let reference = Developer.normalized(try #require(untouched.outputImage))
        let decoder = try #require(Self.developer.rawDecoder(data, maxDimension: nil, anchor: .none))

        #expect(Self.worstDifference(try decoder.negative().image, reference) == 0)
        let moved = try decoder.negative(whiteBalance: Self.tungsten)
        #expect(Self.worstDifference(moved.image, reference) > 0.1, "the white balance changes the develop")
        let back = Self.worstDifference(try decoder.negative().image, reference)
        #expect(back <= Self.backToAsShotTolerance, "back at as shot: \(back)")
    }

    @Test(arguments: SyntheticDNG.Mosaic.allCases, [nil, 256] as [CGFloat?])
    func everyWhiteBalanceMatchesADevelopFromTheFile(mosaic: SyntheticDNG.Mosaic, maxDimension: CGFloat?) throws {
        let data = Self.file(mosaic)
        let decoder = try #require(Self.developer.rawDecoder(data, maxDimension: maxDimension))
        for whiteBalance in Self.whiteBalances {
            let kept = try decoder.negative(whiteBalance: whiteBalance)
            let fresh = try Self.developer.develop(data, maxDimension: maxDimension, whiteBalance: whiteBalance)
            let difference = Self.worstDifference(kept.image, fresh.image)
            // Exact at every white balance; as shot again is within the return tolerance.
            #expect(difference <= Self.backToAsShotTolerance, "white balance \(String(describing: whiteBalance)): \(difference)")
            if whiteBalance != nil { #expect(difference == 0, "white balance \(String(describing: whiteBalance))") }
            #expect(kept.exposureAnchorStops == fresh.exposureAnchorStops)
            #expect(kept.asShotWhiteBalance == fresh.asShotWhiteBalance)
            #expect(kept.contract == .sceneReferred)
        }
    }

    @Test func theAnchorIsMeasuredOnceAndKeptAcrossWhiteBalances() throws {
        let decoder = try #require(Self.developer.rawDecoder(Self.file(.bayerRGGB)))
        let anchor = decoder.exposureAnchorStops
        #expect(abs(anchor - 2) < 0.01, "a ×4 gain table is 2 stops, measured \(anchor)")
        #expect(try decoder.negative(whiteBalance: Self.tungsten).exposureAnchorStops == anchor)
        #expect(try decoder.negative().exposureAnchorStops == anchor)
    }

    @Test func aGivenAnchorIsUsedInsteadOfMeasuring() throws {
        let decoder = try #require(Self.developer.rawDecoder(Self.file(.linearRGB), exposureAnchorStops: 1.25))
        #expect(decoder.exposureAnchorStops == 1.25)
        #expect(try decoder.negative().exposureAnchorStops == 1.25)
    }

    @Test func aPhotoThatIsNotRAWHasNoDecoderOrAsShotWhiteBalance() throws {
        let jpeg = try EmulsionTestCase.sharedRenderer.export(SceneFixtures.flat(0.18, width: 64, height: 64), format: .jpeg)
        #expect(Self.developer.rawDecoder(jpeg) == nil)
        #expect(Developer.asShotWhiteBalance(of: jpeg) == nil)
    }

    @Test func asShotWhiteBalanceIsReadWithoutDeveloping() throws {
        let data = Self.file(.linearRGB)
        let developed = try Self.developer.develop(data, whiteBalance: Self.tungsten)
        #expect(Developer.asShotWhiteBalance(of: data) == developed.asShotWhiteBalance)
    }
}
