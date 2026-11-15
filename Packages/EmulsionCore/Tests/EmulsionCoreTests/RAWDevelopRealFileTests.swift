import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

@Suite(.enabled(if: RAWDevelopSupport.samplesFolders != nil), .serialized)
struct RAWDevelopRealFileTests {
    static let minimumFilesForHeadroomCheck = 20
    static let minimumFilesAboveFloor = 3
    /// The old develop's max may exceed the new one only by rounding.
    static let maxTolerance = 0.01

    @Test func developedRealFilesKeepHeadroom() throws {
        let urls = try RAWDevelopSupport.sampleURLs()
        try #require(!urls.isEmpty, "EMULSION_RAW_SAMPLES lists no .dng files")
        let developer = RAWDevelopTests.developer
        print("| File | BaselineExposure | Old max | New max | New p99.9 lum | > 1 | > 2 | > 4 |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        var aboveFloor = 0
        for url in urls {
            let raw = try #require(CIRAWFilter(imageURL: url))
            let baseline = raw.baselineExposure
            let old = RAWDevelopSupport.FrameStats(
                Fixtures.linear(try RAWDevelopSupport.preMOV79Negative(raw, maxDimension: RAWDevelopSupport.previewLongEdge).image))
            let developed = try developer.develop(Data(contentsOf: url), maxDimension: RAWDevelopSupport.previewLongEdge)
            #expect(developed.contract == .sceneReferred, "\(url.lastPathComponent) did not develop as RAW")
            let new = RAWDevelopSupport.FrameStats(Fixtures.linear(developed.image))
            let name = url.lastPathComponent
            print(
                "| \(name) | \(Double(baseline).fourDigits) | \(old.maxValue.fourDigits) | \(new.maxValue.fourDigits) | \(new.p999.fourDigits)"
                    + " | \(new.over1.fourDigits) | \(new.over2.fourDigits) | \(new.over4.fourDigits) |"
            )
            #expect(old.isFinite && new.isFinite, "\(name) has non-finite values")
            #expect(new.maxValue >= old.maxValue - Self.maxTolerance, "\(name): new max \(new.maxValue) < old max \(old.maxValue)")
            if new.maxValue > RAWDevelopSupport.headroomFloor { aboveFloor += 1 }
        }
        if urls.count >= Self.minimumFilesForHeadroomCheck {
            #expect(
                aboveFloor >= Self.minimumFilesAboveFloor, "\(aboveFloor) of \(urls.count) files exceed \(RAWDevelopSupport.headroomFloor)")
        }
    }
}
