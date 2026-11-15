import EmulsionKit
import SwiftUI

#if DEBUG
    struct ViewfinderTimingOverlay: View {
        let model: CameraModel

        static var isEnabled: Bool { LaunchArgument.isPresent(LaunchArgument.viewfinderTiming) }

        var body: some View {
            let timing = model.viewfinderTiming
            let milliseconds = timing.meanRenderMilliseconds.formatted(.number.precision(.fractionLength(1)))
            let rate = timing.framesPerSecond.formatted(.number.precision(.fractionLength(0)))
            Text("\(milliseconds) ms · \(rate) fps")
                .font(.caption.monospacedDigit())
                .padding(6)
                .background(.black.opacity(0.6), in: .rect(cornerRadius: 6))
                .allowsHitTesting(false)
        }
    }
#endif
