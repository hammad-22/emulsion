import Testing

@testable import EmulsionKit

@MainActor
enum CameraTestSupport {
    /// A bounded number of turns, not a wall-clock wait (MOV-138).
    static func settle(until condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
    }
}

/// Holds a `MockCameraSource` capture in flight until released.
struct ShutterHold {
    let gate: MockCameraSource.CaptureGate
    private let started: AsyncStream<Void>
    private let releases: AsyncStream<Void>.Continuation

    init() {
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        gate = MockCameraSource.CaptureGate(started: startedContinuation, release: release)
        self.started = started
        releases = releaseContinuation
    }

    func waitUntilCaptureStarts() async {
        for await _ in started { break }
    }

    func release() {
        releases.yield()
    }
}
