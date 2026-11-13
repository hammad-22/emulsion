import CoreImage
import EmulsionFixtures
import Foundation
import Testing

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

    static let tungsten = CameraWhiteBalance(temperature: SyntheticDNG.illuminantAKelvin, tint: 0)
    static let whiteBalances: [CameraWhiteBalance?] = [
        nil, tungsten, CameraWhiteBalance(temperature: 4200, tint: 25), CameraWhiteBalance(temperature: 9000, tint: -40), nil,
    ]

    @Test(arguments: SyntheticDNG.Mosaic.allCases, [nil, 256] as [CGFloat?])
    func everyWhiteBalanceMatchesADevelopFromTheFile(mosaic: SyntheticDNG.Mosaic, maxDimension: CGFloat?) throws {
        let data = Self.file(mosaic)
        let decoder = try #require(Self.developer.rawDecoder(data, maxDimension: maxDimension))
        for whiteBalance in Self.whiteBalances {
            let kept = try decoder.negative(whiteBalance: whiteBalance)
            let fresh = try Self.developer.develop(data, maxDimension: maxDimension, whiteBalance: whiteBalance)
            #expect(Fixtures.linear(kept.image) == Fixtures.linear(fresh.image), "white balance \(String(describing: whiteBalance))")
            #expect(kept.exposureAnchorStops == fresh.exposureAnchorStops)
            #expect(kept.asShotWhiteBalance == fresh.asShotWhiteBalance)
            #expect(kept.contract == .sceneReferred)
        }
    }

    @Test func theWhiteBalanceChangesTheDevelop() throws {
        let decoder = try #require(Self.developer.rawDecoder(Self.file(.linearRGB)))
        let asShot = Fixtures.linear(try decoder.negative().image)
        let corrected = Fixtures.linear(try decoder.negative(whiteBalance: Self.tungsten).image)
        #expect(asShot != corrected)
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
        let jpeg = try #require(
            CIContext(options: [.useSoftwareRenderer: true])
                .jpegRepresentation(of: SceneFixtures.patches(), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        #expect(Self.developer.rawDecoder(jpeg) == nil)
        #expect(Developer.asShotWhiteBalance(of: jpeg) == nil)
    }

    @Test func asShotWhiteBalanceIsReadWithoutDeveloping() throws {
        let data = Self.file(.linearRGB)
        let developed = try Self.developer.develop(data, whiteBalance: Self.tungsten)
        #expect(Developer.asShotWhiteBalance(of: data) == developed.asShotWhiteBalance)
    }
}
