import Foundation

/// Rolling viewfinder performance over the last `window` frames: how long each render took
/// and how many frames reached the screen per second. For the debug overlay.
public struct ViewfinderTiming: Sendable, Equatable {
    private static let window = 60
    private var renderSeconds: [Double] = []
    private var shownAt: [ContinuousClock.Instant] = []

    public init() {}

    public var meanRenderMilliseconds: Double {
        renderSeconds.isEmpty ? 0 : renderSeconds.reduce(0, +) / Double(renderSeconds.count) * 1000
    }

    public var framesPerSecond: Double {
        guard let first = shownAt.first, let last = shownAt.last, first < last else { return 0 }
        return Double(shownAt.count - 1) / (first.duration(to: last) / .seconds(1))
    }

    mutating func record(render: Duration, shownAt instant: ContinuousClock.Instant) {
        renderSeconds.append(render / .seconds(1))
        shownAt.append(instant)
        if renderSeconds.count > Self.window { renderSeconds.removeFirst() }
        if shownAt.count > Self.window { shownAt.removeFirst() }
    }
}
