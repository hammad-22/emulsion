import EmulsionCore
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import EmulsionKit

@MainActor
struct PhotoStoreTests {
    @Test func deleteForgetsCachedPreviews() async throws {
        let library = TestLibrary()
        let store = library.store
        let photo = try store.add(TestPhoto.jpeg, fileExtension: "JPG")
        _ = try await library.renderService.image(store.url(for: photo), photo.adjustments, maxDimension: 512)
        let beforeDelete = await library.renderService.cachedPreviewKeys
        #expect(beforeDelete.count == 1)

        await store.delete(photo.id)

        let afterDelete = await library.renderService.cachedPreviewKeys
        #expect(afterDelete.isEmpty)
        #expect(store.photos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: photo).path))
    }

    @Test func editsPersistAcrossLaunches() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        var edit = photo.adjustments
        edit.exposure = 1
        library.store.update(photo.id, adjustments: edit)

        let reopened = library.reopened()

        #expect(reopened.photos.map(\.id) == [photo.id])
        #expect(reopened.photo(photo.id)?.adjustments.exposure == 1)
        #expect(reopened.photo(photo.id)?.isRAW == false)
    }

    @Test func importNamesTheFileAfterWhatItIs() throws {
        let library = TestLibrary()
        #expect(try library.store.add(TestPhoto.jpeg).fileName.hasSuffix(".jpeg"))
        #expect(try library.store.add(Data("not an image".utf8)).fileName.hasSuffix(".jpg"))
    }

    @Test func grainSeedsAreWholeNumbersInTheKernelsRange() {
        let seeds = (0..<500).map { _ in Adjustments.defaults(for: UUID()).seed }
        #expect(seeds.allSatisfy { (0...1023).contains($0) && $0.rounded() == $0 })
        #expect(Set(seeds).count > 1, "photos get different grain")
    }

    @Test func samplesImportAndRender() async throws {
        let library = TestLibrary()
        try library.store.addSamples()

        #expect(library.store.photos.count == 3)
        #expect(library.reopened().photos.count == 3, "one index write covers the whole batch")
        for photo in library.store.photos {
            let image = try await library.renderService.image(library.store.url(for: photo), photo.adjustments, maxDimension: 300)
            #expect(max(image.width, image.height) == 512, "300 px rounds up to the 512 px step")
        }
    }

    @Test func anIndexFromAnOlderVersionLoadsWithDefaults() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        // As an older app wrote it: before `halation` and `seed` existed.
        let olderIndex = """
            [{"id": "\(photo.id)", "created": 0, "fileName": "\(photo.fileName)", "isRAW": false,
              "adjustments": {"exposure": 1, "warmth": 0, "tint": 0, "color": 0,
                              "highlights": 0, "shadows": 0, "grain": 0.5}}]
            """
        try Data(olderIndex.utf8).write(to: library.indexURL)

        let reopened = library.reopened()

        #expect(reopened.lastError == nil)
        #expect(reopened.photos.map(\.id) == [photo.id])
        let adjustments = try #require(reopened.photo(photo.id)?.adjustments)
        #expect(adjustments.exposure == 1)
        #expect(adjustments.grain == 0.5)
        #expect(adjustments.halation == Adjustments().halation)
    }

    @Test func aRecordMissingItsEditsGetsTheDefaultLook() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let minimalIndex = #"[{"id": "\#(photo.id)", "fileName": "\#(photo.fileName)"}]"#
        try Data(minimalIndex.utf8).write(to: library.indexURL)

        let reopened = library.reopened()

        #expect(reopened.photo(photo.id)?.adjustments == .defaults(for: photo.id))
    }

    @Test func anUnreadableIndexIsKeptAndTheOriginalsStayListed() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let corrupt = Data("[{\"id\": tru".utf8)
        try corrupt.write(to: library.indexURL)

        let reopened = library.reopened()
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(reopened.photos.map(\.id) == [photo.id], "originals are listed again, with the default look")
        #expect(reopened.photo(photo.id)?.adjustments == .defaults(for: photo.id))

        var edit = photo.adjustments
        edit.exposure = 2
        reopened.update(photo.id, adjustments: edit)

        let kept = try FileManager.default.contentsOfDirectory(at: library.folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-unreadable-") }
        #expect(kept.count == 1)
        #expect(try kept.map { try Data(contentsOf: $0) } == [corrupt], "the unreadable index is never overwritten")
        #expect(library.reopened().photo(photo.id)?.adjustments.exposure == 2)
    }

    @Test func aFailedSaveIsReportedAndNotShownAsSaved() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        // A folder where the index should be makes every index write fail.
        try FileManager.default.removeItem(at: library.indexURL)
        try FileManager.default.createDirectory(at: library.indexURL, withIntermediateDirectories: false)

        var edit = photo.adjustments
        edit.exposure = 1
        library.store.update(photo.id, adjustments: edit)

        #expect(library.store.lastError == .librarySaveFailed)
        #expect(library.store.photo(photo.id)?.adjustments == photo.adjustments)
        #expect(throws: EmulsionError.librarySaveFailed) { try library.store.add(TestPhoto.jpeg, fileExtension: "jpg") }
        #expect(library.store.photos.map(\.id) == [photo.id], "a failed import leaves no orphan behind")
        let originals = try FileManager.default.contentsOfDirectory(atPath: library.folder.path(percentEncoded: false))
        #expect(originals.filter { $0.hasSuffix(".jpg") } == [photo.fileName])
    }
}
