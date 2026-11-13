import EmulsionCore
import EmulsionFixtures
import Foundation
import ImageIO
import Testing

@testable import EmulsionKit

@MainActor
struct RenderServiceTests {
    @Test func resizesWithinOneStepReuseTheCachedDevelop() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
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
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))

        let original = try await library.renderService.original(url, maxDimension: 100)

        #expect(max(original.width, original.height) == 100)
        let cached = await library.renderService.cachedPreviewKeys
        #expect(cached.isEmpty, "showing the original doesn't develop the photo")
    }
}

extension RenderServiceTests {
    @Test func thumbnailsAreKeptPerEditAndForgottenWithThePhoto() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
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
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
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
        let url = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))

        _ = try await library.renderService.image(url, .init(), maxDimension: 1200)

        #expect(library.renderService.cachedThumbnail(url, .init(), maxDimension: 1200) == nil)
    }
}

extension RenderServiceTests {
    /// The anchor is measured on the file's first develop and reused for other sizes and the
    /// export, which then match a service that measures it for them.
    @Test func exposureAnchorIsMeasuredOncePerFileAndReused() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"))
        let service = library.renderService
        let fresh = { TestLibrary().renderService }

        #expect(await service.exposureAnchor(url) == nil)
        _ = try await service.image(url, .init(), maxDimension: 256)
        let anchor = try #require(await service.exposureAnchor(url))
        #expect(anchor != 0)

        let reused = try await service.image(url, .init(), maxDimension: 512)
        let measured = try await fresh().image(url, .init(), maxDimension: 512)
        #expect(TestPixels.rgba(reused) == TestPixels.rgba(measured))
        let exported = try await service.export(url, .init(), format: .jpeg)
        let exportedFresh = try await fresh().export(url, .init(), format: .jpeg)
        #expect(TestPixels.rgba(try Self.decoded(exported)) == TestPixels.rgba(try Self.decoded(exportedFresh)))
        #expect(await service.exposureAnchor(url) == anchor)

        await service.forget(url)
        #expect(await service.exposureAnchor(url) == nil)
    }

    private static func decoded(_ data: Data) throws -> CGImage {
        try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    }
}

// MARK: RAW white balance (MOV-10)

extension RenderServiceTests {
    static var tungstenWhiteBalance: Adjustments { whiteBalance(SyntheticDNG.illuminantAKelvin) }

    static func whiteBalance(_ kelvin: Double, tint: Double = 0) -> Adjustments {
        var adjustments = Adjustments.neutral
        adjustments.whiteBalance = CameraWhiteBalance(temperature: kelvin, tint: tint)
        return adjustments
    }

    @Test func newWhiteBalanceRedevelopsAndReplacesTheCachedDevelop() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService
        let key = "\(url.absoluteString)@1024"

        let asShot = try await service.image(url, .neutral, maxDimension: 900)
        let corrected = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.developCount == 2)
        #expect(await service.cachedPreviewKeys == [key], "one develop per photo and size, whatever the white balance")
        #expect(try TestRAW.grayCast(corrected) < TestRAW.grayCast(asShot), "the develop used the new white balance")

        var cooler = Self.tungstenWhiteBalance
        for kelvin in [3000.0, 3200, 3400] {
            cooler.whiteBalance?.temperature = kelvin
            _ = try await service.image(url, cooler, maxDimension: 900)
        }
        #expect(await service.cachedPreviewKeys == [key], "a temperature drag doesn't fill the cache")
        #expect(await service.developCount == 5)
    }

    /// Only a RAW photo develops again for a new white balance; the developer ignores it on others.
    @Test func whiteBalanceRedevelopsOnlyRAWPhotos() async throws {
        let library = TestLibrary()
        let jpeg = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let raw = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService

        _ = try await service.image(jpeg, .neutral, maxDimension: 900)
        _ = try await service.image(jpeg, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.developCount == 1, "a JPEG isn't developed again for a white balance")

        _ = try await service.image(raw, .neutral, maxDimension: 900)
        _ = try await service.image(raw, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.developCount == 3, "a RAW photo is")
    }

    @Test func sameWhiteBalanceReusesTheCachedDevelop() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService
        var warmer = Self.tungstenWhiteBalance
        warmer.warmth = 0.4

        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 900)
        _ = try await service.image(url, warmer, maxDimension: 900)
        #expect(await service.developCount == 1, "printer lights only re-run the look")
    }

    /// The anchor is measured as shot, so a new white balance develops again with the file's anchor.
    @Test func newWhiteBalanceReusesTheExposureAnchor() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"))
        let service = library.renderService

        _ = try await service.image(url, .neutral, maxDimension: 512)
        let anchor = try #require(await service.exposureAnchor(url))
        #expect(anchor != 0)
        let reused = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 512)
        #expect(await service.developCount == 2, "the white balance developed again")
        #expect(await service.exposureAnchor(url) == anchor)
        let measured = try await TestLibrary().renderService.image(url, Self.tungstenWhiteBalance, maxDimension: 512)
        #expect(TestPixels.rgba(reused) == TestPixels.rgba(measured))
    }

    @Test func exportDevelopsAtTheWhiteBalance() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService

        func decoded(_ adjustments: Adjustments) async throws -> CGImage {
            let data = try await service.export(url, adjustments, format: .jpeg)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let asShot = try TestRAW.grayCast(await decoded(.neutral))
        let corrected = try TestRAW.grayCast(await decoded(Self.tungstenWhiteBalance))
        #expect(corrected < asShot, "gray cast \(corrected) codes at 2856 K, \(asShot) as shot")
        // Measured 0 codes at 2856 K, 98 as shot.
        #expect(corrected <= 1, "gray cast \(corrected) codes at 2856 K")
    }
}

// MARK: Interactive RAW white balance (MOV-137)

extension RenderServiceTests {
    /// Each step of a white balance drag on the open photo matches a develop from the file
    /// (a service that hasn't opened it), without reading the file again.
    @Test func theOpenPhotoChangesWhiteBalanceWithoutReadingTheFileAgain() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"))
        let service = library.renderService
        let fromTheFile = TestLibrary().renderService
        service.open(url)

        let asShot = try await service.image(url, .neutral, maxDimension: 1200)
        for kelvin in [3000.0, 3400, 4200, 9000] {
            let step = try await service.image(url, Self.whiteBalance(kelvin, tint: 12), maxDimension: 1200)
            let reference = try await fromTheFile.image(url, Self.whiteBalance(kelvin, tint: 12), maxDimension: 1200)
            #expect(TestPixels.rgba(step) == TestPixels.rgba(reference), "\(kelvin) K")
        }
        #expect(await service.fileReadCount == 1)
        #expect(await service.developCount == 5, "every step is a new develop of the kept decoder")
        #expect(await fromTheFile.fileReadCount == 4, "a photo that isn't open reads its file for each")

        let backToAsShot = try await service.image(url, .neutral, maxDimension: 1200)
        #expect(TestPixels.rgba(backToAsShot) == TestPixels.rgba(asShot))
        #expect(await service.fileReadCount == 1)
        #expect(await service.developCount == 6, "as shot again is developed, not looked up")
    }

    @Test func theOpenPhotoMeasuresItsExposureAnchorOnceAndExportsWithIt() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"))
        let service = library.renderService
        service.open(url)

        _ = try await service.image(url, .neutral, maxDimension: 512)
        let anchor = try #require(await service.exposureAnchor(url))
        #expect(anchor != 0)
        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 512)
        #expect(await service.exposureAnchor(url) == anchor)

        let exported = try await service.export(url, Self.tungstenWhiteBalance, format: .jpeg)
        let exportedFresh = try await TestLibrary().renderService.export(url, Self.tungstenWhiteBalance, format: .jpeg)
        #expect(TestPixels.rgba(try Self.decoded(exported)) == TestPixels.rgba(try Self.decoded(exportedFresh)))
    }

    @Test func onlyTheOpenPhotoKeepsADecoder() async throws {
        let library = TestLibrary()
        let first = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let second = library.store.url(for: try await library.store.add(TestPhoto.anchoredRAW, fileExtension: "dng"))
        let jpeg = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService

        _ = try await service.image(first, .neutral, maxDimension: 900)
        #expect(await service.keptDecoderURL == nil, "a photo nobody opened keeps none")

        service.open(first)
        _ = try await service.image(first, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.keptDecoderURL == first)
        _ = try await service.image(second, .neutral, maxDimension: 300)
        #expect(await service.keptDecoderURL == first, "a thumbnail of another photo doesn't take it")

        service.open(second)
        _ = try await service.image(second, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.keptDecoderURL == second, "one decoder: the newly opened photo's replaces it")

        service.open(jpeg)
        _ = try await service.image(jpeg, .neutral, maxDimension: 900)
        #expect(await service.keptDecoderURL == nil, "a photo that isn't RAW has no decoder")
    }

    @Test func closingOrForgettingThePhotoReleasesItsDecoder() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService

        service.open(url)
        _ = try await service.image(url, .neutral, maxDimension: 900)
        await service.close(url).value
        #expect(await service.keptDecoderURL == nil)

        service.open(url)
        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 900)
        #expect(await service.keptDecoderURL == url)
        await service.forget(url)
        #expect(await service.keptDecoderURL == nil)
    }

    /// A close that lands after the photo was opened again (the editor reopened at once)
    /// leaves the new editor's decoder alone.
    @Test func aLateCloseDoesNotReleaseAReopenedPhoto() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService

        service.open(url)
        _ = try await service.image(url, .neutral, maxDimension: 900)
        let closing = service.close(url)
        service.open(url)
        await closing.value
        #expect(await service.keptDecoderURL == url)
    }

    /// A smaller preview of the open photo (its library thumbnail beside the editor) is resized
    /// from the kept decoder; only a larger one reads the file again.
    @Test func smallerPreviewsOfTheOpenPhotoReuseItsDecoder() async throws {
        let library = TestLibrary()
        let url = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let service = library.renderService
        service.open(url)

        _ = try await service.image(url, .neutral, maxDimension: 300)
        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 200)
        #expect(await service.fileReadCount == 1)
        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 300)
        #expect(await service.fileReadCount == 1)
        _ = try await service.image(url, Self.tungstenWhiteBalance, maxDimension: 600)
        #expect(await service.fileReadCount == 2, "a larger preview needs a larger decode")
    }

    @Test func asShotWhiteBalanceIsReadFromRAWFilesOnly() async throws {
        let library = TestLibrary()
        let raw = library.store.url(for: try await library.store.add(TestRAW.tungstenTaggedAsDaylight, fileExtension: "dng"))
        let jpeg = library.store.url(for: try await library.store.add(TestPhoto.jpeg, fileExtension: "jpg"))
        let service = library.renderService

        let asShot = try #require(await service.asShotWhiteBalance(raw))
        #expect(abs(asShot.temperature - TestRAW.taggedKelvin) < TestRAW.asShotTemperatureTolerance)
        #expect(await service.asShotWhiteBalance(jpeg) == nil)
        #expect(await service.asShotWhiteBalance(library.folder.appending(path: "missing.dng")) == nil)
        #expect(await service.fileReadCount == 0, "reading it doesn't develop the photo")
    }
}
