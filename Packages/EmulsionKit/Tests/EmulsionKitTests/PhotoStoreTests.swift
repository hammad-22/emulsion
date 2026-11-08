import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct PhotoStoreTests {
    @Test func deleteForgetsCachedPreviews() async throws {
        let folder = TestPhoto.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = RenderService()
        let store = PhotoStore(folder: folder, renderService: service)
        let photo = try store.add(TestPhoto.jpeg, fileExtension: "JPG")
        _ = try await service.image(store.url(for: photo), photo.adjustments, maxDimension: 512)
        let beforeDelete = await service.cachedPreviewKeys
        #expect(beforeDelete.count == 1)

        await store.delete(photo.id)

        let afterDelete = await service.cachedPreviewKeys
        #expect(afterDelete.isEmpty)
        #expect(store.photos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: photo).path))
    }

    @Test func editsPersistAcrossLaunches() throws {
        let folder = TestPhoto.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhotoStore(folder: folder, renderService: RenderService())
        let photo = try store.add(TestPhoto.jpeg, fileExtension: "jpg")
        var edit = photo.adjustments
        edit.exposure = 1
        store.update(photo.id, adjustments: edit)

        let reopened = PhotoStore(folder: folder, renderService: RenderService())

        #expect(reopened.photos.map(\.id) == [photo.id])
        #expect(reopened.photo(photo.id)?.adjustments.exposure == 1)
        #expect(reopened.photo(photo.id)?.isRAW == false)
    }
}
