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

    @Test func deletingASelectionRemovesOnlyThosePhotos() async throws {
        let library = TestLibrary()
        let photos = try (0..<3).map { _ in try library.store.add(TestPhoto.jpeg, fileExtension: "jpg") }

        await library.store.delete([photos[0].id, photos[2].id])

        #expect(library.reopened().photos.map(\.id) == [photos[1].id])
        #expect(!FileManager.default.fileExists(atPath: library.store.url(for: photos[0]).path(percentEncoded: false)))
    }

    @Test func failedSelectionDeletionKeepsEveryRecordAndOriginal() async throws {
        let library = TestLibrary()
        let photos = try (0..<3).map { _ in try library.store.add(TestPhoto.jpeg, fileExtension: "jpg") }
        let saved = try Data(contentsOf: library.store.indexURL)
        try FileManager.default.removeItem(at: library.store.indexURL)
        try FileManager.default.createDirectory(at: library.store.indexURL, withIntermediateDirectories: false)

        await library.store.delete([photos[0].id, photos[2].id])

        #expect(library.store.lastError == .librarySaveFailed)
        #expect(Set(library.store.photos.map(\.id)) == Set(photos.map(\.id)))
        for photo in photos {
            #expect(FileManager.default.fileExists(atPath: library.store.url(for: photo).path(percentEncoded: false)))
        }
        try FileManager.default.removeItem(at: library.store.indexURL)
        try saved.write(to: library.store.indexURL)
        #expect(Set(library.reopened().photos.map(\.id)) == Set(photos.map(\.id)))
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

    @Test func aFailedOriginalRemovalIsReported() async throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let original = library.store.url(for: photo)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try TestPhoto.jpeg.write(to: original.appending(path: "blocked.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: original.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: original.path(percentEncoded: false)) }

        await library.store.delete(photo.id)

        #expect(library.store.lastError == .libraryDeleteFailed)
        #expect(FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))
    }

    @Test func aSaveFailureIsReportedAfterADeleteFailure() async throws {
        let library = TestLibrary()
        let other = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let original = library.store.url(for: photo)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try TestPhoto.jpeg.write(to: original.appending(path: "blocked.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: original.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: original.path(percentEncoded: false)) }
        await library.store.delete(photo.id)
        #expect(library.store.lastError == .libraryDeleteFailed)
        library.store.lastError = nil

        let folder = library.folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
        var edit = other.adjustments
        edit.exposure = 1
        library.store.update(other.id, adjustments: edit)

        #expect(library.store.lastError == .librarySaveFailed)
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
        try Data(olderIndex.utf8).write(to: library.store.indexURL)

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
        try Data(minimalIndex.utf8).write(to: library.store.indexURL)

        let reopened = library.reopened()

        #expect(reopened.photo(photo.id)?.adjustments == .defaults(for: photo.id))
    }

    @Test func aBadRecordDoesNotDiscardOtherPhotosEdits() throws {
        let library = TestLibrary()
        let kept = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let damaged = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        var edit = kept.adjustments
        edit.exposure = 1.5
        library.store.update(kept.id, adjustments: edit)
        var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: library.store.indexURL)) as? [[String: Any]])
        let index = try #require(records.firstIndex { $0["id"] as? String == damaged.id.uuidString })
        records[index]["id"] = "invalid UUID"
        let corrupt = try JSONSerialization.data(withJSONObject: records)
        try corrupt.write(to: library.store.indexURL)

        let reopened = library.reopened()

        #expect(reopened.lastError == .libraryUnreadable)
        #expect(reopened.photo(kept.id)?.adjustments == edit)
        #expect(Set(reopened.photos.map(\.id)) == Set([kept.id, damaged.id]))
        let backup = try #require(
            FileManager.default.contentsOfDirectory(at: library.folder, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("library-unreadable-") })
        #expect(try Data(contentsOf: backup) == corrupt)
    }

    @Test func anUnreadableIndexIsKeptAndTheOriginalsStayListed() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let corrupt = Data("[{\"id\": tru".utf8)
        try corrupt.write(to: library.store.indexURL)

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

    @Test func anIndexThatCantBeReadNowIsLeftAlone() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let index = library.store.indexURL
        let saved = try Data(contentsOf: index)
        // As when file protection keeps the index locked at launch.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: index.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: index.path(percentEncoded: false)) }

        let reopened = library.reopened()
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(reopened.photos.map(\.id) == [photo.id])
        var edit = photo.adjustments
        edit.exposure = 1
        reopened.update(photo.id, adjustments: edit)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: index.path(percentEncoded: false))
        #expect(try Data(contentsOf: index) == saved, "never moved aside or overwritten")
        #expect(library.reopened().photo(photo.id)?.adjustments == photo.adjustments)
    }

    @Test func anInaccessibleLibraryFolderIsNotTreatedAsAnEmptyLibrary() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let saved = try Data(contentsOf: library.store.indexURL)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: library.folder.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.folder.path(percentEncoded: false))
        }

        let reopened = library.reopened()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.folder.path(percentEncoded: false))

        #expect(reopened.lastError == .libraryUnreadable)
        #expect(throws: EmulsionError.librarySaveFailed) { try reopened.add(TestPhoto.jpeg, fileExtension: "jpg") }
        #expect(try Data(contentsOf: library.store.indexURL) == saved)
        #expect(library.reopened().photo(photo.id) != nil)
    }

    @Test func originalsAreRecoveredWhenTheIndexIsMissing() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        try FileManager.default.removeItem(at: library.store.indexURL)

        let reopened = library.reopened()

        #expect(reopened.photos.map(\.id) == [photo.id])
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(library.reopened().photos.map(\.id) == [photo.id])
    }

    @Test func aFailedSaveIsReportedAndNotShownAsSaved() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        // A folder where the index should be makes every index write fail.
        try FileManager.default.removeItem(at: library.store.indexURL)
        try FileManager.default.createDirectory(at: library.store.indexURL, withIntermediateDirectories: false)

        var edit = photo.adjustments
        edit.exposure = 1
        library.store.update(photo.id, adjustments: edit)

        #expect(library.store.lastError == .librarySaveFailed)
        #expect(library.store.photo(photo.id)?.adjustments == photo.adjustments)
        library.store.lastError = nil
        edit.exposure = 2
        library.store.update(photo.id, adjustments: edit)
        #expect(library.store.lastError == nil, "reported once, not on every slider rest")
        #expect(throws: EmulsionError.librarySaveFailed) { try library.store.add(TestPhoto.jpeg, fileExtension: "jpg") }
        #expect(library.store.photos.map(\.id) == [photo.id], "a failed import leaves no orphan behind")
        let originals = try FileManager.default.contentsOfDirectory(atPath: library.folder.path(percentEncoded: false))
        #expect(originals.filter { $0.hasSuffix(".jpg") } == [photo.fileName])
    }
}
