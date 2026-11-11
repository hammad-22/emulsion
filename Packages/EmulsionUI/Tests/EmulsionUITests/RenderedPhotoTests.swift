import CoreGraphics
import Testing

@testable import EmulsionUI

struct RenderedPhotoTests {
    private static func pixel() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    @Test func aStandInShowsUntilTheFirstRender() throws {
        let latest = try Self.pixel()
        #expect(RenderedPhoto.shownImage(rendered: nil, thumbnail: nil, latestEdit: latest, failed: false) === latest)
    }

    @Test func aFailedRenderIsNotHiddenByAStandIn() throws {
        let latest = try Self.pixel()
        #expect(RenderedPhoto.shownImage(rendered: nil, thumbnail: nil, latestEdit: latest, failed: true) == nil)
    }

    @Test func anExactThumbnailStillShowsAfterAFailure() throws {
        let thumbnail = try Self.pixel()
        #expect(RenderedPhoto.shownImage(rendered: nil, thumbnail: thumbnail, latestEdit: nil, failed: true) === thumbnail)
    }
}
