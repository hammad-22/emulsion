import CoreImage
import CoreVideo
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct ViewfinderTests {
    @Test func mockDeliversUprightBGRAFrames() async throws {
        let source = MockCameraSource()
        let frames = source.frames()
        _ = try await source.start(lens: .wide)
        defer { Task { await source.stop() } }

        var iterator = frames.makeAsyncIterator()
        let frame = try #require(await iterator.next())

        #expect(CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == kCVPixelFormatType_32BGRA)
        #expect(frame.rotationAngle == 0, "already upright")
        #expect(CVPixelBufferGetHeight(frame.pixelBuffer) > CVPixelBufferGetWidth(frame.pixelBuffer), "portrait, like a phone held upright")
    }

    @Test func viewfinderImageIsFittedWithTheFramesAspect() async throws {
        let library = TestLibrary()
        let frame = try Self.frame(width: 640, height: 480)

        let image = try await library.renderService.viewfinderImage(frame, maxDimension: 320)

        #expect(image.width == 320)
        #expect(image.height == 240)
    }

    @Test func viewfinderImageIsTurnedUpright() async throws {
        let library = TestLibrary()
        let frame = CameraFrame(pixelBuffer: try Self.frame(width: 640, height: 480).pixelBuffer, rotationAngle: 90)

        let image = try await library.renderService.viewfinderImage(frame, maxDimension: 320)

        #expect(image.width == 240)
        #expect(image.height == 320)
    }

    @Test func modelStreamsRenderedFramesAndTimesThem() async throws {
        let library = TestLibrary()
        let model = CameraModel(source: MockCameraSource(), store: library.store)
        let images = model.viewfinderImages(maxDimension: 256)
        await model.start()

        var iterator = images.makeAsyncIterator()
        let first = try #require(await iterator.next())
        _ = await iterator.next()
        await model.stop()

        #expect(max(first.width, first.height) == 256)
        #expect(model.viewfinderTiming.meanRenderMilliseconds > 0)
        #expect(model.viewfinderTiming.framesPerSecond > 0)
    }

    /// A frame filled with a mid grey, tagged sRGB like the mock camera's.
    static func frame(width: Int, height: Int) throws -> CameraFrame {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        let pixels = try #require(buffer)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        CIContext().render(grey, to: pixels, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: sRGB)
        CVBufferSetAttachment(pixels, kCVImageBufferCGColorSpaceKey, sRGB, .shouldPropagate)
        return CameraFrame(pixelBuffer: pixels)
    }
}

/// Mean viewfinder render time at a typical iPhone viewfinder size. Opt-in: EMULSION_PERF=1.
@MainActor
struct ViewfinderPerformanceProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run"))
    func viewfinderRenderTime() async throws {
        let library = TestLibrary()
        let frame = try ViewfinderTests.frame(width: 4032 / 3, height: 3024 / 3)
        let longEdge: CGFloat = 1280
        let frames = 120
        _ = try await library.renderService.viewfinderImage(frame, maxDimension: longEdge)  // warm up the renderer

        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            for _ in 0..<frames { _ = try await library.renderService.viewfinderImage(frame, maxDimension: longEdge) }
        }
        let mean = String(format: "%.2f", elapsed / .milliseconds(1) / Double(frames))
        print("viewfinderImage: \(mean) ms mean over \(frames) frames at \(Int(longEdge)) px")
    }
}
