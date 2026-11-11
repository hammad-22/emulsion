import Synchronization

/// The newest-only frame stream a camera source feeds from its capture queue.
final class FrameStream: Sendable {
    private let continuation = Mutex<AsyncStream<CameraFrame>.Continuation?>(nil)

    /// A new stream; the previous one finishes, so there's only ever one viewfinder.
    func makeStream() -> AsyncStream<CameraFrame> {
        let (stream, new) = AsyncStream.makeStream(of: CameraFrame.self, bufferingPolicy: .bufferingNewest(1))
        continuation.withLock {
            $0?.finish()
            $0 = new
        }
        return stream
    }

    func yield(_ frame: CameraFrame) {
        continuation.withLock { _ = $0?.yield(frame) }
    }
}
