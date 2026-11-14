import Synchronization

/// A stream a camera source feeds from its own queues, to one consumer at a time.
final class SourceStream<Element: Sendable>: Sendable {
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
    private let continuation = Mutex<AsyncStream<Element>.Continuation?>(nil)

    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy) {
        self.bufferingPolicy = bufferingPolicy
    }

    deinit {
        continuation.withLock { $0?.finish() }
    }

    func makeStream() -> AsyncStream<Element> {
        let (stream, new) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        continuation.withLock {
            $0?.finish()
            $0 = new
        }
        return stream
    }

    func yield(_ element: Element) {
        continuation.withLock { _ = $0?.yield(element) }
    }
}

extension SourceStream where Element == CameraFrame {
    static func frames() -> SourceStream { SourceStream(bufferingPolicy: .bufferingNewest(1)) }
}

extension SourceStream where Element == CameraEvent {
    static func events() -> SourceStream { SourceStream(bufferingPolicy: .unbounded) }
}
