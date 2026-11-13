import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionKit

/// Mac timing of a slider drag through `RenderService`, as the editor makes it: one render per
/// slider step at an editor-sized preview, each waiting for the last. Opt-in: EMULSION_PERF=1.
/// The files are synthetic and uncompressed, so the decode isn't a real ProRAW's (JPEG XL).
@MainActor @Suite(.serialized)
struct SliderDragProbe {
    private static let steps = 30
    private static let rounds = 5
    private static let previewPixels: CGFloat = 1600

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil), arguments: SyntheticDNG.Mosaic.allCases)
    func updatesPerSecond(mosaic: SyntheticDNG.Mosaic) async throws {
        let library = TestLibrary()
        // 12 MP (4032 × 3024), with a gain table so the develop measures an exposure anchor.
        let chart = PatchChart(RAWDevelopChart.scene, cell: 504)
        let raw = RAWDevelopChart.dng(mosaic, chart: chart, profile: SyntheticDNG.Profile(gainTableGain: 4))
        let photo = try await library.store.add(raw, fileExtension: "dng")
        let url = library.store.url(for: photo)
        let service = library.renderService
        let session = EditSession(photo: photo, store: library.store)
        defer { session.close() }

        let clock = ContinuousClock()
        let open = try await clock.measure { _ = try await service.image(url, .init(), maxDimension: Self.previewPixels) }

        /// Median updates per second over `rounds` drags of `steps` renders each.
        func updatesPerSecond(_ edit: (Double) -> Adjustments) async throws -> Double {
            var rates: [Double] = []
            for round in 0..<Self.rounds {
                let duration = try await clock.measure {
                    for step in 1...Self.steps {
                        // A different value every round, so no step is a cached develop.
                        let adjustments = edit((Double(round) + Double(step) / Double(Self.steps)) / Double(Self.rounds))
                        _ = try await service.image(url, adjustments, maxDimension: Self.previewPixels)
                    }
                }
                rates.append(Double(Self.steps) / Self.seconds(duration))
            }
            return rates.sorted()[Self.rounds / 2]
        }
        let printerLights = try await updatesPerSecond { amount in
            var adjustments = Adjustments()
            adjustments.warmth = amount
            return adjustments
        }
        let whiteBalance = try await updatesPerSecond { amount in
            var adjustments = Adjustments()
            adjustments.whiteBalance = CameraWhiteBalance(temperature: 3000 + 6000 * amount, tint: 0)
            return adjustments
        }
        print(
            String(
                format:
                    "12 MP %@, %d px preview: open %.0f ms; Warmth drag %.0f updates/s; white balance drag %.0f updates/s (%d file reads)",
                "\(mosaic)", Int(Self.previewPixels), 1000 * Self.seconds(open), printerLights, whiteBalance, await service.fileReadCount))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
