import CoreVideo
import Testing

@testable import EmulsionKit

@MainActor
struct MockCameraSourceTests {
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

    @Test func mockFramesStayTheFrameSizeThroughThePan() async throws {
        let source = MockCameraSource()
        _ = try await source.start(lens: .wide)
        await source.stop()

        for step in 0..<64 {
            let frame = try #require(await source.frame(at: Double(step) * 0.137))
            #expect(CVPixelBufferGetWidth(frame.pixelBuffer) == Int(MockCameraSource.frameSize.width), "step \(step)")
            #expect(CVPixelBufferGetHeight(frame.pixelBuffer) == Int(MockCameraSource.frameSize.height), "step \(step)")
        }
    }
}
