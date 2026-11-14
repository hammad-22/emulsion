import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// RAW white balance on real DNGs from EMULSION_RAW_SAMPLES (never checked in). Re-saved files
/// whose AsShotNeutral is [1, 1, 1] only test the mechanism, not the camera's white balance.
@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct CameraWhiteBalanceRealFileTests {
    /// Measured worst 1.6e-4 (any channel and pixel, relative to max(1, value), 1024 px; absolute
    /// 0.0024 on a file anchored +2.95 stops) setting the as-shot values back.
    static let asShotRepeatTolerance = 4e-4
    static let cool = 3200.0
    static let daylight = 6500.0

    /// Mean R/G and B/G over the frame.
    static func ratios(_ pixels: [SIMD3<Double>]) -> SIMD2<Double> {
        let mean = pixels.reduce(SIMD3<Double>.zero, +) / Double(pixels.count)
        return SIMD2(mean.x / mean.y, mean.z / mean.y)
    }

    @Test func realFilesFollowTheWhiteBalance() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        let edge = RAWDevelopSupport.previewLongEdge
        print(
            "| File | As shot K | Tint | R/G, B/G as shot | R/G, B/G \(Int(Self.cool)) K | R/G, B/G \(Int(Self.daylight)) K"
                + " | Max rel. diff, as-shot values set | Anchor (as shot / \(Int(Self.cool)) / \(Int(Self.daylight))) |")
        print("| --- | ---: | ---: | --- | --- | --- | ---: | --- |")
        var worstRepeat = 0.0
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let plain = try developer.develop(data, maxDimension: edge)
            let asShot = try #require(plain.asShotWhiteBalance, "\(name) is not RAW")
            let explicit = try developer.develop(data, maxDimension: edge, whiteBalance: asShot)
            let cool = try developer.develop(
                data, maxDimension: edge, whiteBalance: CameraWhiteBalance(temperature: Self.cool, tint: asShot.tint))
            let daylight = try developer.develop(
                data, maxDimension: edge, whiteBalance: CameraWhiteBalance(temperature: Self.daylight, tint: asShot.tint))
            let plainPixels = Fixtures.linear(plain.image)
            let repeatDifference =
                zip(plainPixels, Fixtures.linear(explicit.image)).map { abs($0 - $1).max() / max(1, abs($0).max()) }.max() ?? .nan
            worstRepeat = max(worstRepeat, repeatDifference)
            let (shotRatios, coolRatios, daylightRatios) = (
                Self.ratios(plainPixels), Self.ratios(Fixtures.linear(cool.image)), Self.ratios(Fixtures.linear(daylight.image))
            )
            func pair(_ r: SIMD2<Double>) -> String { "\(r.x.fourDigits), \(r.y.fourDigits)" }
            let anchors = [plain, cool, daylight].map { String(format: "%+.4f", $0.exposureAnchorStops) }.joined(separator: " / ")
            print(
                "| \(name) | \(asShot.temperature.fourDigits) | \(asShot.tint.fourDigits) | \(pair(shotRatios)) | \(pair(coolRatios))"
                    + " | \(pair(daylightRatios)) | \(repeatDifference.fourDigits) | \(anchors) |")
            #expect(repeatDifference <= Self.asShotRepeatTolerance, "\(name): \(repeatDifference)")
            #expect(cool.exposureAnchorStops == plain.exposureAnchorStops, "\(name): anchor moved at \(Self.cool) K")
            #expect(daylight.exposureAnchorStops == plain.exposureAnchorStops, "\(name): anchor moved at \(Self.daylight) K")
            #expect(
                coolRatios.x / coolRatios.y < daylightRatios.x / daylightRatios.y,
                "\(name): R/B at \(Self.cool) K is not below \(Self.daylight) K")
        }
        print("worst difference setting the as-shot values back: \(worstRepeat.fourDigits)")
    }
}
