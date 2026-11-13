import EmulsionCore
import Testing

@testable import EmulsionKit

@MainActor
struct EditSessionTests {
    @Test func closeWritesTheLastChangeAtOnce() async throws {
        let library = TestLibrary()
        let session = EditSession(photo: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"), store: library.store)

        session.adjustments.exposure = 1.5
        session.close()

        #expect(library.reopened().photos.first?.adjustments.exposure == 1.5)
    }

    @Test func changesSaveOnceSlidersRest() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let session = EditSession(photo: photo, store: library.store)

        session.adjustments.warmth = 0.5
        let pendingSave = try #require(session.pendingSave)
        #expect(library.store.photo(photo.id)?.adjustments.warmth == 0, "not written mid-drag")
        await pendingSave.value

        #expect(library.store.photo(photo.id)?.adjustments.warmth == 0.5)
    }

    @Test func resetKeepsTheGrainPattern() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let session = EditSession(photo: photo, store: library.store)
        session.adjustments.grain = 1
        session.adjustments.seed = 0

        session.reset()

        #expect(session.adjustments == photo.adjustments)
    }

    @Test func resetReturnsTheWhiteBalanceToAsShot() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng")
        let session = EditSession(photo: photo, store: library.store)
        session.adjustments.whiteBalance = CameraWhiteBalance(temperature: 3200, tint: 0)
        #expect(session.isEdited)

        session.reset()

        #expect(session.adjustments.whiteBalance == nil)
    }

    @Test func aSessionIsEditedUntilReset() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg")
        let session = EditSession(photo: photo, store: library.store)
        #expect(!session.isEdited)
        #expect(!photo.isEdited)

        session.adjustments.exposure = 1
        session.close()
        #expect(session.isEdited)
        #expect(library.store.photo(photo.id)?.isEdited == true)

        session.reset()
        #expect(!session.isEdited)
    }

    @Test func aRAWPhotoLearnsItsAsShotWhiteBalance() async throws {
        let library = TestLibrary()
        let raw = EditSession(
            photo: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"), store: library.store)
        let jpeg = EditSession(photo: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"), store: library.store)
        #expect(raw.asShotWhiteBalance == nil, "not read until the editor asks")

        await raw.readAsShotWhiteBalance()
        await jpeg.readAsShotWhiteBalance()

        let asShot = try #require(raw.asShotWhiteBalance)
        #expect(abs(asShot.temperature - TestRAW.taggedKelvin) < TestRAW.asShotTemperatureTolerance)
        #expect(jpeg.asShotWhiteBalance == nil, "white balance doesn't apply to a photo that isn't RAW")
    }

    @Test func draggingWhiteBalanceBackToAsShotLeavesThePhotoUnedited() async throws {
        let library = TestLibrary()
        let session = EditSession(
            photo: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"), store: library.store)
        await session.readAsShotWhiteBalance()
        let temperature = try #require(AdjustmentGroup.whiteBalance.controls(whiteBalanceAsShot: session.asShotWhiteBalance).first)
        let asShotValue = session.adjustments[keyPath: temperature.keyPath]

        session.adjustments[keyPath: temperature.keyPath] = asShotValue + 40
        #expect(session.isEdited)
        session.adjustments[keyPath: temperature.keyPath] = asShotValue
        #expect(!session.isEdited)
    }

    /// The editor's photo keeps its RAW decoder until the editor closes.
    @Test func theOpenPhotoKeepsItsDecoderUntilTheSessionCloses() async throws {
        let library = TestLibrary()
        let photo = try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng")
        let session = EditSession(photo: photo, store: library.store)
        let service = library.renderService

        _ = try await service.image(session.url, session.adjustments, maxDimension: 900)
        #expect(await service.keptDecoderURL == session.url)

        session.save()
        session.adjustments.exposure = 1
        _ = try await service.image(session.url, session.adjustments, maxDimension: 900)
        #expect(await service.keptDecoderURL == session.url, "saving (the Mac window going inactive) keeps it")

        session.close()
        await service.close(session.url).value
        #expect(await service.keptDecoderURL == nil)
        #expect(library.store.photo(photo.id)?.adjustments.exposure == 1)
    }
}
