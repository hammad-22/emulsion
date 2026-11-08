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
}
