import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct PhotoStoreRecoveryTests {
    @Test func anIndexFromAnOlderVersionLoadsWithDefaults() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
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

    @Test func aRecordMissingItsEditsGetsTheDefaultLook() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let minimalIndex = #"[{"id": "\#(photo.id)", "fileName": "\#(photo.fileName)"}]"#
        try Data(minimalIndex.utf8).write(to: library.store.indexURL)

        let reopened = library.reopened()

        #expect(reopened.photo(photo.id)?.adjustments == .defaults(for: photo.id))
    }

    @Test func aBadRecordDoesNotDiscardOtherPhotosEdits() async throws {
        let library = TestLibrary()
        let kept = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let damaged = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
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
        let backup = try #require(try library.unreadableIndexBackups.first)
        #expect(try Data(contentsOf: backup) == corrupt)
    }

    @Test func anUnreadableIndexIsKeptAndTheOriginalsStayListed() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let corrupt = Data("[{\"id\": tru".utf8)
        try corrupt.write(to: library.store.indexURL)

        let reopened = library.reopened()
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(reopened.photos.map(\.id) == [photo.id], "originals are listed again, with the default look")
        #expect(reopened.photo(photo.id)?.adjustments == .defaults(for: photo.id))

        var edit = photo.adjustments
        edit.exposure = 2
        reopened.update(photo.id, adjustments: edit)

        let kept = try library.unreadableIndexBackups
        #expect(kept.count == 1)
        #expect(try kept.map { try Data(contentsOf: $0) } == [corrupt], "the unreadable index is never overwritten")
        #expect(library.reopened().photo(photo.id)?.adjustments.exposure == 2)
    }

    @Test func anIndexThatCantBeReadNowIsLeftAlone() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let index = library.store.indexURL
        let saved = try Data(contentsOf: index)
        // As when file protection keeps the index locked at launch.
        try FilePermissions.set(FilePermissions.none, at: index)
        defer { try? FilePermissions.set(FilePermissions.file, at: index) }

        let reopened = library.reopened()
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(reopened.photos.map(\.id) == [photo.id])
        var edit = photo.adjustments
        edit.exposure = 1
        reopened.update(photo.id, adjustments: edit)

        try FilePermissions.set(FilePermissions.file, at: index)
        #expect(try Data(contentsOf: index) == saved, "never moved aside or overwritten")
        #expect(library.reopened().photo(photo.id)?.adjustments == photo.adjustments)
    }

    @Test func anInaccessibleLibraryFolderIsNotTreatedAsAnEmptyLibrary() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let saved = try Data(contentsOf: library.store.indexURL)
        try FilePermissions.set(FilePermissions.none, at: library.folder)
        defer { try? FilePermissions.set(FilePermissions.folder, at: library.folder) }

        let reopened = library.reopened()
        try FilePermissions.set(FilePermissions.folder, at: library.folder)

        #expect(reopened.lastError == .libraryUnreadable)
        await #expect(throws: EmulsionError.librarySaveFailed) { try await reopened.add(TestPhoto.jpeg, fileExtension: "jpg") }
        #expect(try Data(contentsOf: library.store.indexURL) == saved)
        #expect(library.reopened().photo(photo.id) != nil)
    }

    @Test func originalsAreRecoveredWhenTheIndexIsMissing() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        try FileManager.default.removeItem(at: library.store.indexURL)

        let reopened = library.reopened()

        #expect(reopened.photos.map(\.id) == [photo.id])
        #expect(reopened.lastError == .libraryUnreadable)
        #expect(library.reopened().photos.map(\.id) == [photo.id])
    }
}
