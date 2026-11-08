import EmulsionCore
import Testing

@testable import EmulsionKit

@MainActor
struct EditSessionTests {
    @Test func closeWritesTheLastChangeAtOnce() throws {
        let library = TestLibrary()
        let session = EditSession(photo: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"), store: library.store)

        session.adjustments.exposure = 1.5
        session.close()

        #expect(library.reopened().photos.first?.adjustments.exposure == 1.5)
    }

    @Test func changesSaveOnceSlidersRest() async throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let session = EditSession(photo: photo, store: library.store)

        session.adjustments.warmth = 0.5
        let pendingSave = try #require(session.pendingSave)
        #expect(library.store.photo(photo.id)?.adjustments.warmth == 0, "not written mid-drag")
        await pendingSave.value

        #expect(library.store.photo(photo.id)?.adjustments.warmth == 0.5)
    }

    @Test func resetKeepsTheGrainPattern() throws {
        let library = TestLibrary()
        let photo = try library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let session = EditSession(photo: photo, store: library.store)
        session.adjustments.grain = 1
        session.adjustments.seed = 0

        session.reset()

        #expect(session.adjustments == photo.adjustments)
    }
}
