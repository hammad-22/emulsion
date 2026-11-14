import Foundation

/// Render time and frame rate over the last `window` frames, for the debug overlay.
public struct ViewfinderTiming: Sendable {
    private static let window = 60
    private var samples: [(renderSeconds: Double, shownAt: ContinuousClock.Instant)] = []

    public init() {}

    public var meanRenderMilliseconds: Double {
        samples.isEmpty ? 0 : samples.map(\.renderSeconds).reduce(0, +) / Double(samples.count) * 1000
    }

    public var framesPerSecond: Double {
        guard let first = samples.first?.shownAt, let last = samples.last?.shownAt, first < last else { return 0 }
        return Double(samples.count - 1) / (first.duration(to: last) / .seconds(1))
    }

    mutating func record(render: Duration, shownAt instant: ContinuousClock.Instant) {
        samples.append((render / .seconds(1), instant))
        if samples.count > Self.window { samples.removeFirst() }
    }
}
