import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct PhotoStoreFailureTests {
    @Test func failedSelectionDeletionKeepsEveryRecordAndOriginal() async throws {
        let library = TestLibrary()
        let photos = try await library.addPhotos(3)
        let saved = try Data(contentsOf: library.store.indexURL)
        try library.blockIndexWrites()

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

    @Test func aFailedOriginalRemovalIsReported() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let original = try library.blockRemoval(of: photo)
        defer { try? FilePermissions.set(FilePermissions.folder, at: original) }

        await library.store.delete(photo.id)

        #expect(library.store.lastError == .libraryDeleteFailed)
        #expect(FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))
    }

    @Test func aSaveFailureIsReportedAfterADeleteFailure() async throws {
        let library = TestLibrary()
        let other = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let original = try library.blockRemoval(of: photo)
        defer { try? FilePermissions.set(FilePermissions.folder, at: original) }
        await library.store.delete(photo.id)
        #expect(library.store.lastError == .libraryDeleteFailed)
        library.store.lastError = nil

        try FilePermissions.set(FilePermissions.readOnlyFolder, at: library.folder)
        defer { try? FilePermissions.set(FilePermissions.folder, at: library.folder) }
        var edit = other.adjustments
        edit.exposure = 1
        library.store.update(other.id, adjustments: edit)

        #expect(library.store.lastError == .librarySaveFailed)
    }

    @Test func aFailedSaveIsReportedAndNotShownAsSaved() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        try library.blockIndexWrites()

        var edit = photo.adjustments
        edit.exposure = 1
        library.store.update(photo.id, adjustments: edit)

        #expect(library.store.lastError == .librarySaveFailed)
        #expect(library.store.photo(photo.id)?.adjustments == photo.adjustments)
        library.store.lastError = nil
        edit.exposure = 2
        library.store.update(photo.id, adjustments: edit)
        #expect(library.store.lastError == nil, "reported once, not on every slider rest")
        await #expect(throws: EmulsionError.librarySaveFailed) { try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg") }
        #expect(library.store.photos.map(\.id) == [photo.id], "a failed import leaves no orphan behind")
        let originals = try FileManager.default.contentsOfDirectory(atPath: library.folder.path(percentEncoded: false))
        #expect(originals.filter { $0.hasSuffix(".jpg") } == [photo.fileName])
    }
}
