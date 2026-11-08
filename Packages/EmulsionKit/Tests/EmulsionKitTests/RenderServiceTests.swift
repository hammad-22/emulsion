import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct RenderServiceTests {
    @Test func resizesWithinOneStepReuseTheCachedDevelop() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService
        let name = url.lastPathComponent

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
