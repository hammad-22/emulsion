import Foundation
import Testing

@testable import EmulsionKit

struct RenderServiceTests {
    @Test func resizesWithinOneStepReuseTheCachedDevelop() async throws {
        let folder = TestPhoto.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("photo.jpg")
        try TestPhoto.jpeg.write(to: url)
        let service = RenderService()

        _ = try await service.image(url, .init(), maxDimension: 900)
        _ = try await service.image(url, .init(), maxDimension: 1024)
        let afterSmallResize = await service.cachedPreviewKeys
        #expect(afterSmallResize == ["photo.jpg@1024"])

        _ = try await service.image(url, .init(), maxDimension: 1025)
        let afterLargeResize = await service.cachedPreviewKeys
        #expect(afterLargeResize == ["photo.jpg@1024", "photo.jpg@1280"])
    }
}
