import EmulsionKit
import SwiftUI

#if DEBUG
    /// Frame time and rate, for profiling on device (`--viewfinder-timing`).
    struct ViewfinderTimingOverlay: View {
        let model: CameraModel

        static var isEnabled: Bool { LaunchArgument.isPresent(LaunchArgument.viewfinderTiming) }

        private let padding: CGFloat = 6
        private let cornerRadius: CGFloat = 6
        private let backgroundOpacity = 0.6

        var body: some View {
            let timing = model.viewfinderTiming
            let milliseconds = timing.meanRenderMilliseconds.formatted(.number.precision(.fractionLength(1)))
            let rate = timing.framesPerSecond.formatted(.number.precision(.fractionLength(0)))
            Text("\(milliseconds) ms · \(rate) fps")
                .font(.caption.monospacedDigit())
                .padding(padding)
                .background(.black.opacity(backgroundOpacity), in: .rect(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
        }
    }
#endif
