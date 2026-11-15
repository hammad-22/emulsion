import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing

@testable import EmulsionKit

enum TestFrames {
    /// A mid grey frame, tagged sRGB like the mock camera's.
    static func grey(width: Int, height: Int) throws -> CameraFrame {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CameraFrame.sRGB,
                bitmapInfo: CameraFrame.bgra))
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage().flatMap(CameraFrame.init(drawing:)))
    }

    /// The first bundled sample at its own size (1800 × 1200).
    static func sample() throws -> CameraFrame {
        let url = try #require(PhotoStore.sampleURLs.first)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap(CameraFrame.init(drawing:)))
    }
}

extension TestPixels {
    /// Mean red minus mean blue, in 8-bit codes.
    static func redOverBlue(_ image: CGImage) -> Double {
        let bytes = rgba(image)
        let pixels = bytes.count / 4
        let red = stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        let blue = stride(from: 2, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
        return Double(red - blue) / Double(pixels)
    }
}

extension RenderService {
    /// Blocks rather than awaits: an actor runs other work at every suspension.
    func occupy(until hold: ActorHold) {
        hold.occupy()
    }
}

final class ActorHold: Sendable {
    private let released = DispatchSemaphore(value: 0)
    private let occupying = Mutex(false)
    private let (occupied, signalOccupied) = AsyncStream<Void>.makeStream()

    var isOccupying: Bool { occupying.withLock { $0 } }

    func waitUntilOccupied() async {
        for await _ in occupied { return }
    }

    func release() {
        released.signal()
    }

    func occupy() {
        occupying.withLock { $0 = true }
        signalOccupied.yield()
        released.wait()
        occupying.withLock { $0 = false }
    }
}
