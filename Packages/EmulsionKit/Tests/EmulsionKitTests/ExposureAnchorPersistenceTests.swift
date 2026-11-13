import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionKit

/// The RAW exposure anchor is kept on the photo record (MOV-141), so a relaunch develops with it
/// instead of measuring the file again.
@MainActor
struct ExposureAnchorPersistenceTests {
    @Test func aRelaunchUsesTheStoredAnchorWithoutMeasuringAgain() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        let first = try await library.renderService.image(url, .init(), maxDimension: 512)
        let stored = try await Self.storedAnchor(of: photo.id, in: library.store)
        #expect(stored.stops != 0)
        #expect(stored.stops == library.renderService.exposureAnchor(url))

        let reopened = library.reopened()
        #expect(reopened.photo(photo.id)?.exposureAnchor == stored)
        let again = try await reopened.renderService.image(url, .init(), maxDimension: 512)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 0)
        #expect(TestPixels.rgba(again) == TestPixels.rgba(first))
    }

    /// MOV-10: the anchor is measured as shot, so a new white balance after a relaunch reuses it.
    @Test func aNewWhiteBalanceAfterARelaunchReusesTheStoredAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        _ = try await library.renderService.image(url, .init(), maxDimension: 512)
        _ = try await Self.storedAnchor(of: photo.id, in: library.store)
        var warm = Adjustments()
        warm.whiteBalance = CameraWhiteBalance(temperature: 2856, tint: 0)

        let reopened = library.reopened()
        let reused = try await reopened.renderService.image(url, warm, maxDimension: 512)
        let measured = try await TestLibrary().renderService.image(url, warm, maxDimension: 512)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 0)
        #expect(TestPixels.rgba(reused) == TestPixels.rgba(measured))
    }

    /// Records from before MOV-141 have no anchor: the first develop measures it once and saves it.
    @Test func aRecordWithoutAnAnchorIsMeasuredOnceAndSaved() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let olderIndex = #"[{"id": "\#(photo.id)", "fileName": "\#(photo.fileName)", "isRAW": true}]"#
        try Data(olderIndex.utf8).write(to: library.store.indexURL)

        let migrated = library.reopened()
        #expect(migrated.photo(photo.id)?.exposureAnchor == nil)
        _ = try await migrated.renderService.image(migrated.url(for: photo), .init(), maxDimension: 256)
        #expect(await migrated.renderService.exposureAnchorMeasurements == 1)
        let stored = try await Self.storedAnchor(of: photo.id, in: migrated)

        #expect(library.reopened().photo(photo.id)?.exposureAnchor == stored)
    }

    /// A stored anchor belongs to the file it was measured from; a replaced file is measured again.
    @Test func aChangedOriginalIsMeasuredAgain() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        _ = try await library.renderService.image(url, .init(), maxDimension: 256)
        let stale = try await Self.storedAnchor(of: photo.id, in: library.store)
        let replaced = RAWDevelopChart.dng(
            .bayerRGGB, chart: RAWDevelopChart.chart(), baselineStops: 0.5, profile: SyntheticDNG.Profile(gainTableGain: 8))
        try replaced.write(to: url)

        let reopened = library.reopened()
        _ = try await reopened.renderService.image(url, .init(), maxDimension: 256)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 1)
        let fresh = try await Self.storedAnchor(of: photo.id, in: reopened) { $0 != stale }
        #expect(fresh.source != stale.source)
    }

    @Test func photosThatArentRAWStoreNoAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)
        await Self.settle()

        #expect(library.store.photo(photo.id)?.exposureAnchor == nil)
    }

    /// The anchor reaches the record on the main actor after the develop that measured it.
    private static func storedAnchor(
        of id: UUID, in store: PhotoStore, where accepted: (StoredExposureAnchor) -> Bool = { _ in true }
    ) async throws -> StoredExposureAnchor {
        for _ in 0..<1000 {
            if let anchor = store.photo(id)?.exposureAnchor, accepted(anchor) { return anchor }
            await Task.yield()
        }
        return try #require(store.photo(id)?.exposureAnchor.flatMap { accepted($0) ? $0 : nil }, "anchor never saved")
    }

    private static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
