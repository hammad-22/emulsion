import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct ExposureAnchorRealFileTests {
    // Measured tolerances, about 2× the worst on macOS 27.2: docs/CONSTANTS.md, "Test tolerances".
    static let appleMedianTolerance = 1.15
    static let megapixelGapTolerance = 0.5
    static let largeMegapixels = 40.0
    static let smallMegapixels = 20.0
    static let secondPreviewLongEdge: CGFloat = 512
    static let anchorRepeatTolerance = 1e-6

    static func medianLuminance(_ image: CIImage) -> Double {
        RAWDevelopSupport.FrameStats(Fixtures.linear(image)).medianLuminance
    }

    static func appleDefault(_ data: Data, maxDimension: CGFloat) throws -> CIImage {
        let raw = try RAWDevelopSupport.filter(data)
        Developer.applyPreviewScale(raw, maxDimension: maxDimension, allowsDraftMode: false)
        return try #require(raw.outputImage)
    }

    @Test func anchoredDevelopsMatchApplesMidtones() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        let edge = RAWDevelopSupport.previewLongEdge
        print("| File | MP | BaselineExposure | Anchor (stops) | Median before | Median after | Median Apple | log2(after ÷ Apple) |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        var gaps: [(megapixels: Double, stops: Double)] = []
        for url in urls {
            let name = url.lastPathComponent
            let data = try Data(contentsOf: url)
            let raw = try RAWDevelopSupport.filter(data)
            let megapixels = Double(raw.nativeSize.width * raw.nativeSize.height) / 1e6
            let before = try developer.develop(data, maxDimension: edge, anchor: .none)
            let after = try developer.develop(data, maxDimension: edge)
            let again = try developer.develop(data, maxDimension: Self.secondPreviewLongEdge)
            let anchor = after.exposureAnchorStops
            let (beforeMedian, afterMedian) = (Self.medianLuminance(before.image), Self.medianLuminance(after.image))
            let appleMedian = Self.medianLuminance(try Self.appleDefault(data, maxDimension: edge))
            let gap = log2(afterMedian / appleMedian)
            gaps.append((megapixels, gap))
            print(
                "| \(name) | \(megapixels.fourDigits) | \(Double(raw.baselineExposure).fourDigits) | \(String(format: "%+.3f", anchor))"
                    + " | \(beforeMedian.fourDigits) | \(afterMedian.fourDigits) | \(appleMedian.fourDigits) | \(String(format: "%+.3f", gap)) |"
            )
            #expect(anchor.isFinite && ExposureAnchor.range.contains(anchor), "\(name): anchor \(anchor)")
            let repeated = again.exposureAnchorStops
            #expect(abs(repeated - anchor) <= Self.anchorRepeatTolerance, "\(name): \(repeated) at 512 px vs \(anchor) at 1024 px")
            #expect(abs(gap) <= Self.appleMedianTolerance, "\(name): log2(after ÷ Apple) \(gap)")
        }
        let large = gaps.filter { $0.megapixels >= Self.largeMegapixels }.map(\.stops)
        let small = gaps.filter { $0.megapixels < Self.smallMegapixels }.map(\.stops)
        let worst = gaps.map { abs($0.stops) }.max() ?? .nan
        let meanAbs = gaps.map { abs($0.stops) }.reduce(0, +) / Double(gaps.count)
        print("worst |log2(after ÷ Apple)| \(worst.fourDigits), mean \(meanAbs.fourDigits) stops")
        if urls.count >= RAWDevelopRealFileTests.minimumFilesForHeadroomCheck, !large.isEmpty, !small.isEmpty {
            let gap = large.reduce(0, +) / Double(large.count) - small.reduce(0, +) / Double(small.count)
            print("≥ \(Self.largeMegapixels) MP minus < \(Self.smallMegapixels) MP: \(String(format: "%+.3f", gap)) stops")
            #expect(abs(gap) <= Self.megapixelGapTolerance, "megapixel gap \(gap)")
        }
    }
}
