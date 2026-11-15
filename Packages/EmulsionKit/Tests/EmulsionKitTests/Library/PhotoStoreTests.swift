import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct PhotoStoreTests {
    @Test func aCancelledImportDoesNotPublishOrLeaveAnOriginal() async throws {
        let library = TestLibrary()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.store.add(TestPhoto.jpeg)
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled import succeeded")
        } catch is CancellationError {
        }
        #expect(library.store.photos.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.folder.path).isEmpty)
    }

    @Test func deleteForgetsCachedPreviews() async throws {
        let library = TestLibrary()
        let store = library.store
        let photo = try await store.add(TestPhoto.jpeg, fileExtension: "JPG")
        _ = try await library.renderService.image(store.url(for: photo), photo.adjustments, maxDimension: 512)
        let beforeDelete = await library.renderService.cachedPreviewKeys
        #expect(beforeDelete.count == 1)

        await store.delete(photo.id)

        let afterDelete = await library.renderService.cachedPreviewKeys
        #expect(afterDelete.isEmpty)
        #expect(store.photos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: photo).path))
    }

    @Test func deletingASelectionRemovesOnlyThosePhotos() async throws {
        let library = TestLibrary()
        let photos = try await library.addPhotos(3)

        await library.store.delete([photos[0].id, photos[2].id])

        #expect(library.reopened().photos.map(\.id) == [photos[1].id])
        #expect(!FileManager.default.fileExists(atPath: library.store.url(for: photos[0]).path(percentEncoded: false)))
    }

    @Test func changingTheEditLeavesTheOriginalUntouched() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg", look: TestLooks.curated(3).adjustments)
        let original = try Data(contentsOf: library.store.url(for: photo))
        #expect(original == TestPhoto.jpeg)

        var cool = try TestLooks.curated(2).adjustments
        cool.seed = photo.adjustments.seed
        library.store.update(photo.id, adjustments: cool)

        #expect(library.store.photo(photo.id)?.adjustments == cool)
        #expect(try Data(contentsOf: library.store.url(for: photo)) == original)
    }

    @Test func editsPersistAcrossLaunches() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        var edit = photo.adjustments
        edit.exposure = 1
        library.store.update(photo.id, adjustments: edit)

        let reopened = library.reopened()

        #expect(reopened.photos.map(\.id) == [photo.id])
        #expect(reopened.photo(photo.id)?.adjustments.exposure == 1)
        #expect(reopened.photo(photo.id)?.isRAW == false)
    }

    @Test func importNamesTheFileAfterWhatItIs() async throws {
        let library = TestLibrary()
        #expect(try await library.store.add(TestPhoto.jpeg).fileName.hasSuffix(".jpeg"))
        await #expect(throws: EmulsionError.unsupportedPhoto) { try await library.store.add(Data("not an image".utf8)) }
    }

    @Test func grainSeedsAreWholeNumbersInTheKernelsRange() {
        let seeds = (0..<500).map { _ in Adjustments.defaults(for: UUID()).seed }
        #expect(seeds.allSatisfy { (0...1023).contains($0) && $0.rounded() == $0 })
        #expect(Set(seeds).count > 1, "photos get different grain")
    }

    @Test func samplesImportAndRender() async throws {
        let library = TestLibrary()
        try await library.store.addSamples()

        #expect(library.store.photos.count == 3)
        #expect(library.reopened().photos.count == 3, "one index write covers the whole batch")
        for photo in library.store.photos {
            let image = try await library.renderService.image(library.store.url(for: photo), photo.adjustments, maxDimension: 300)
            #expect(max(image.width, image.height) == 512, "300 px rounds up to the 512 px step")
        }
    }
}
