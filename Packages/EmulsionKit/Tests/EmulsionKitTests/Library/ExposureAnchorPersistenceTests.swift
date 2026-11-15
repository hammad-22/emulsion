import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionKit

/// Saves are awaited through `PhotoStore.exposureAnchorsSaved()`, never a wall-clock deadline: a
/// busy CI runner took about 145 s a test (MOV-163). The time limit only stops a save that never comes.
@MainActor @Suite(.timeLimit(.minutes(10)))
struct ExposureAnchorPersistenceTests {
    @Test func aRelaunchUsesTheStoredAnchorWithoutMeasuringAgain() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        // Larger than a thumbnail, so the relaunch develops again instead of reading a stored one.
        let first = try await library.renderService.image(url, .init(), maxDimension: 600)
        let stored = await Self.storedAnchor(of: photo.id, in: library.store)
        #expect(stored.stops != 0)
        #expect(stored.stops == library.renderService.exposureAnchor(url))

        let reopened = library.reopened()
        #expect(reopened.photo(photo.id)?.exposureAnchor == stored)
        let again = try await reopened.renderService.image(url, .init(), maxDimension: 600)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 0)
        #expect(TestPixels.rgba(again) == TestPixels.rgba(first))
    }

    @Test func aNewWhiteBalanceAfterARelaunchReusesTheStoredAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        _ = try await library.renderService.image(url, .init(), maxDimension: 512)
        _ = await Self.storedAnchor(of: photo.id, in: library.store)
        var warm = Adjustments()
        warm.whiteBalance = CameraWhiteBalance(temperature: 2856, tint: 0)

        let reopened = library.reopened()
        let reused = try await reopened.renderService.image(url, warm, maxDimension: 512)
        let measured = try await TestLibrary().renderService.image(url, warm, maxDimension: 512)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 0)
        #expect(TestPixels.rgba(reused) == TestPixels.rgba(measured))
    }

    @Test func aRecordWithoutAnAnchorIsMeasuredOnceAndSaved() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let olderIndex = #"[{"id": "\#(photo.id)", "fileName": "\#(photo.fileName)", "isRAW": true}]"#
        try Data(olderIndex.utf8).write(to: library.store.indexURL)

        let migrated = library.reopened()
        #expect(migrated.photo(photo.id)?.exposureAnchor == nil)
        _ = try await migrated.renderService.image(migrated.url(for: photo), .init(), maxDimension: 256)
        #expect(await migrated.renderService.exposureAnchorMeasurements == 1)
        let stored = await Self.storedAnchor(of: photo.id, in: migrated)

        #expect(library.reopened().photo(photo.id)?.exposureAnchor == stored)
    }

    @Test func aChangedOriginalIsMeasuredAgain() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let url = library.store.url(for: photo)
        _ = try await library.renderService.image(url, .init(), maxDimension: 256)
        let stale = await Self.storedAnchor(of: photo.id, in: library.store)
        try Self.brighterRAW.write(to: url)

        let reopened = library.reopened()
        _ = try await reopened.renderService.image(url, .init(), maxDimension: 256)

        #expect(await reopened.renderService.exposureAnchorMeasurements == 1)
        let fresh = await Self.storedAnchor(of: photo.id, in: reopened) { $0 != stale }
        #expect(fresh.source != stale.source)
    }

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

    @Test func everyAnchorOfABurstIsSaved() async throws {
        let library = TestLibrary()
        let photos = [
            try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"),
            try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"),
            try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"),
        ]
        for photo in photos {
            _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)
        }
        for photo in photos { _ = await Self.storedAnchor(of: photo.id, in: library.store) }

        let reopened = library.reopened()
        #expect(photos.allSatisfy { reopened.photo($0.id)?.exposureAnchor != nil })
    }

    @Test func aFailedAnchorSaveIsReported() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        try library.blockIndexWrites()

        _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)
        while library.store.lastError == nil { await library.store.exposureAnchorsSaved() }

        #expect(library.store.lastError == .librarySaveFailed)
        #expect(library.store.photo(photo.id)?.exposureAnchor == nil)
    }

    @Test func photosThatArentRAWStoreNoAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        _ = try await library.renderService.image(library.store.url(for: photo), .init(), maxDimension: 256)

        #expect(await library.renderService.exposureAnchorMeasurements == 0)
        #expect(library.store.photo(photo.id)?.exposureAnchor == nil)
    }

    @Test func aRAWRecordWithoutItsKindStillKeepsItsAnchor() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng")
        let olderIndex = #"[{"id": "\#(photo.id)", "fileName": "\#(photo.fileName)"}]"#
        try Data(olderIndex.utf8).write(to: library.store.indexURL)

        let migrated = library.reopened()
        _ = try await migrated.renderService.image(migrated.url(for: photo), .init(), maxDimension: 256)

        _ = await Self.storedAnchor(of: photo.id, in: migrated)
    }

    /// A different file at the same path: the anchor fixture with a stronger gain table.
    private static let brighterRAW = RAWDevelopChart.dng(
        .bayerRGGB, chart: RAWDevelopChart.chart(), baselineStops: 0.5, profile: SyntheticDNG.Profile(gainTableGain: 8))

    private static func storedAnchor(
        of id: UUID, in store: PhotoStore, where accepted: (StoredExposureAnchor) -> Bool = { _ in true }
    ) async -> StoredExposureAnchor {
        while true {
            if let anchor = store.photo(id)?.exposureAnchor, accepted(anchor) { return anchor }
            await store.exposureAnchorsSaved()
        }
    }
}
