import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct RenderServiceTests {
    @Test func resizesWithinOneStepReuseTheCachedDevelop() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService
        let name = url.absoluteString

        _ = try await service.image(url, .init(), maxDimension: 900)
        _ = try await service.image(url, .init(), maxDimension: 1024)
        let afterSmallResize = await service.cachedPreviewKeys
        #expect(afterSmallResize == ["\(name)@1024"])

        _ = try await service.image(url, .init(), maxDimension: 1025)
        let afterLargeResize = await service.cachedPreviewKeys
        #expect(afterLargeResize == ["\(name)@1024", "\(name)@1280"])
    }

    @Test func originalIsUndevelopedAndFitsTheSize() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))

        let original = try await library.renderService.original(url, maxDimension: 100)

        #expect(max(original.width, original.height) == 100)
        let cached = await library.renderService.cachedPreviewKeys
        #expect(cached.isEmpty, "showing the original doesn't develop the photo")
    }
}

extension RenderServiceTests {
    @Test func thumbnailsAreKeptPerEditAndForgottenWithThePhoto() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService
        var warmer = Adjustments()
        warmer.warmth = 0.5

        #expect(service.cachedThumbnail(url, .init(), maxDimension: 300) == nil)
        let rendered = try await service.image(url, .init(), maxDimension: 300)
        #expect(service.cachedThumbnail(url, .init(), maxDimension: 300) === rendered)
        #expect(service.cachedThumbnail(url, warmer, maxDimension: 300) == nil, "a different edit is a different thumbnail")

        await service.forget(url)
        #expect(service.cachedThumbnail(url, .init(), maxDimension: 300) == nil)
    }

    @Test func latestEditorRenderIsKeptUntilThePhotoIsForgotten() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService

        _ = try await service.original(url, maxDimension: 900)
        #expect(service.latestRender(url) == nil, "an original is never a stand-in for the edit")
        let rendered = try await service.image(url, .init(), maxDimension: 900)
        #expect(service.latestRender(url) === rendered)
        _ = try await service.image(url, .init(), maxDimension: 300)
        #expect(service.latestRender(url) === rendered, "thumbnails don't replace it")

        await service.forget(url)
        #expect(service.latestRender(url) == nil)
    }

    @Test func sameNamedPhotosInDifferentFoldersHaveSeparateCaches() async throws {
        let library = TestLibrary()
        _ = library.store
        let firstFolder = library.folder.appending(path: "first")
        let secondFolder = library.folder.appending(path: "second")
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = firstFolder.appending(path: "photo.jpg")
        let second = secondFolder.appending(path: "photo.jpg")
        try Data(contentsOf: PhotoStore.sampleURLs[0]).write(to: first)
        try Data(contentsOf: PhotoStore.sampleURLs[1]).write(to: second)
        let service = library.renderService

        _ = try await service.image(first, .init(), maxDimension: 300)
        #expect(service.cachedThumbnail(second, .init(), maxDimension: 300) == nil)
        _ = try await service.image(second, .init(), maxDimension: 300)
        let keys = await service.cachedPreviewKeys
        #expect(keys.count == 2, "the developed sources are independent, too")

        await service.forget(first)
        let remaining = await service.cachedPreviewKeys
        #expect(remaining == ["\(second.absoluteString)@512"])
    }

    @Test func editorSizedRendersAreNotKept() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))

        _ = try await library.renderService.image(url, .init(), maxDimension: 1200)

        #expect(library.renderService.cachedThumbnail(url, .init(), maxDimension: 1200) == nil)
    }
}
