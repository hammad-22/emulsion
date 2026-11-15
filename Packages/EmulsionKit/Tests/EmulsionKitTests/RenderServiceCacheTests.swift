import CoreImage
import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

/// What the render service keeps between renders and launches (MOV-163).
@MainActor
struct RenderServiceCacheTests {
    @Test func thumbnailsOnDiskSurviveARelaunch() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let rendered = try await library.renderService.image(url, .init(), maxDimension: 300)

        let relaunched = library.reopened().renderService
        #expect(relaunched.cachedThumbnail(url, .init(), maxDimension: 300) == nil, "the main actor never reads the disk")
        let stored = try await relaunched.image(url, .init(), maxDimension: 300)

        #expect(await relaunched.developCount == 0)
        #expect(stored.width == rendered.width && stored.height == rendered.height)
        #expect(relaunched.cachedThumbnail(url, .init(), maxDimension: 300) === stored, "kept in memory once read")
    }

    @Test func aChangedEditOrFileMissesTheStoredThumbnail() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        _ = try await library.renderService.image(url, .init(), maxDimension: 300)
        var warmer = Adjustments()
        warmer.warmth = 0.5

        let relaunched = library.reopened().renderService
        _ = try await relaunched.image(url, warmer, maxDimension: 300)
        #expect(await relaunched.developCount == 1, "another edit")
        _ = try await relaunched.image(url, .init(), maxDimension: 400)
        #expect(await relaunched.developCount == 1, "another size within the step reuses the develop")

        try TestPhoto.detailedJPEG.write(to: url)
        let afterChange = library.reopened().renderService
        _ = try await afterChange.image(url, .init(), maxDimension: 300)
        #expect(await afterChange.developCount == 1, "the file changed")
    }

    @Test func forgettingAPhotoRemovesItsStoredThumbnails() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let other = library.store.url(for: try await library.store.add(TestPhoto.detailedJPEG, fileExtension: "jpg"))
        _ = try await library.renderService.image(url, .init(), maxDimension: 300)
        _ = try await library.renderService.image(other, .init(), maxDimension: 300)

        await library.renderService.forget(url)

        let relaunched = library.reopened().renderService
        _ = try await relaunched.image(other, .init(), maxDimension: 300)
        #expect(await relaunched.developCount == 0)
        _ = try await relaunched.image(url, .init(), maxDimension: 300)
        #expect(await relaunched.developCount == 1)
    }

    @Test func storedThumbnailsAreTrimmedToTheirLimit() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.detailedJPEG, fileExtension: "jpg"))
        let image = try await library.renderService.image(url, .init(), maxDimension: 300)
        let files = ThumbnailFiles(parent: library.thumbnailsFolder, byteLimit: Self.trimLimit)

        for seed in 0..<40 {
            var edit = Adjustments()
            edit.seed = Double(seed)
            files.keep(image, try #require(ThumbnailCache.Key(url, edit, maxDimension: 300)))
        }

        let stored = try FileManager.default.contentsOfDirectory(at: files.folder, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try stored.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(bytes <= Self.trimLimit)
        #expect(!stored.isEmpty, "trimming keeps the most recent")
    }

    @Test func editorPreviewsAreCappedInSize() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(Self.largeJPEG, fileExtension: "jpg"))

        let preview = try await library.renderService.image(url, .init(), maxDimension: 5120)

        #expect(max(preview.width, preview.height) == Int(RenderService.maxPreviewDimension))
    }

    @Test func previewCacheStaysWithinItsByteBudget() async throws {
        let library = TestLibrary()
        let service = library.renderService
        for _ in 0..<3 {
            let url = library.store.url(for: try await library.store.add(Self.largeJPEG, fileExtension: "jpg"))
            for pixels in [2560, 2304, 2048] as [CGFloat] { _ = try await service.image(url, .init(), maxDimension: pixels) }
        }

        #expect(await service.cachedPreviewBytes <= RenderService.previewCacheBytes)
        #expect(await service.cachedPreviewKeys.count > 1)
    }

    private static let trimLimit = 256 << 10

    /// 4000 × 3000 gray, larger than the preview cap; encoded on the CPU (MOV-127).
    private static let largeJPEG: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = CIImage(color: CIColor(red: 0.4, green: 0.45, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        return CIContext(options: [.useSoftwareRenderer: true]).jpegRepresentation(of: image, colorSpace: space)!
    }()
}
