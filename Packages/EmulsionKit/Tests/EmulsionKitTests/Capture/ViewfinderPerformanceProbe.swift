import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

/// Mean viewfinder render time at iPhone viewfinder sizes. Opt-in: EMULSION_PERF=1; Mac numbers only.
@MainActor
struct ViewfinderPerformanceProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil, "set EMULSION_PERF=1 to run"))
    func viewfinderRenderTime() async throws {
        let library = TestLibrary()
        let frame = try TestFrames.grey(width: 4032 / 2, height: 3024 / 2)
        let frames = 120
        for (name, look) in [("default look", Adjustments()), ("no grain or halation", Adjustments.neutral)] {
            for longEdge: CGFloat in [1280, 1920] {
                _ = try await library.renderService.viewfinderImage(frame, look, maxDimension: longEdge)  // warm up
                let elapsed = try await ContinuousClock().measure {
                    for _ in 0..<frames { _ = try await library.renderService.viewfinderImage(frame, look, maxDimension: longEdge) }
                }
                let mean = String(format: "%.2f", elapsed / .milliseconds(1) / Double(frames))
                print("viewfinderImage, \(name): \(mean) ms mean over \(frames) frames at \(Int(longEdge)) px")
            }
        }
    }
}
