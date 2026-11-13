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
        try Self.brighterRAW.write(to: url)

        let reopened = library.reopened()
        _ = try await reopened.renderService.image(url, .init(), maxDimension: 256)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 1)
        let fresh = try await Self.storedAnchor(of: photo.id, in: reopened) { $0 != stale }
        #expect(fresh.source != stale.source)
    }

    /// Within a session too: the service checks the file at each develop.
    @Test func anOriginalChangedDuringASessionIsMeasuredAgain() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        let service = library.renderService
        _ = try await service.image(url, .init(), maxDimension: 256)
        try Self.brighterRAW.write(to: url)

        _ = try await service.image(url, .init(), maxDimension: 512)

        #expect(await service.exposureAnchorMeasurements == 2)
    }

    /// Anchors measured together reach the index in one save.
    @Test func anchorsMeasuredTogetherAreSavedTogether() async throws {
        let library = TestLibrary()
        let first = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let second = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        for photo in [first, second] {
            _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)
        }
        _ = try await Self.storedAnchor(of: first.id, in: library.store)

        #expect(library.store.photo(second.id)?.exposureAnchor != nil)
    }

    @Test func photosThatArentRAWStoreNoAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)
        try await Task.sleep(for: PhotoStore.exposureAnchorSaveDelay * 2)

        #expect(library.store.photo(photo.id)?.exposureAnchor == nil)
    }

    /// The anchor fixture with a stronger gain table: a different file at the same path.
    private static let brighterRAW = RAWDevelopChart.dng(
        .bayerRGGB, chart: RAWDevelopChart.chart(), baselineStops: 0.5, profile: SyntheticDNG.Profile(gainTableGain: 8))

    /// The anchor reaches the record once the store saves it, `exposureAnchorSaveDelay` after the
    /// develop that measured it.
    private static func storedAnchor(
        of id: UUID, in store: PhotoStore, where accepted: (StoredExposureAnchor) -> Bool = { _ in true }
    ) async throws -> StoredExposureAnchor {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if let anchor = store.photo(id)?.exposureAnchor, accepted(anchor) { return anchor }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("anchor never saved")
        throw CancellationError()
    }
}
