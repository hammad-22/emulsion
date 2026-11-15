import Darwin
import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionKit

/// Mac timings of the library render queue (MOV-163): a slider step asked for behind queued
/// thumbnails or a running export, and how many develops a relaunched library repeats.
/// Opt-in: EMULSION_PERF=1. Synthetic, uncompressed DNGs, so decodes aren't a real ProRAW's.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["EMULSION_PERF"] != nil))
struct RenderQueueProbe {
    private static let thumbnailPixels: CGFloat = 300
    private static let previewPixels: CGFloat = 1600
    private static let queuedThumbnails = 8
    /// 12 MP (4032 × 3024) and 48 MP (8064 × 6048) charts.
    private static let raw12 = RAWDevelopChart.dng(.bayerRGGB, chart: RAWDevelopChart.chart(cell: 504))
    private static let clock = ContinuousClock()
    private static let sliderStep = {
        var step = Adjustments()
        step.warmth = 0.3
        return step
    }()

    private static func addRAWs(to library: TestLibrary) async throws -> [URL] {
        var urls: [URL] = []
        for _ in 0..<queuedThumbnails { urls.append(library.store.url(for: try await library.store.add(raw12, fileExtension: "dng"))) }
        return urls
    }

    /// Thumbnails at the editor's priority, then at the library's lower one (`RenderedPhoto`).
    @Test(arguments: [TaskPriority.userInitiated, .utility])
    func sliderStepBehindQueuedThumbnails(priority: TaskPriority) async throws {
        let library = TestLibrary()
        let service = library.renderService
        let thumbnails = try await Self.addRAWs(to: library)
        let edited = library.store.url(for: try await library.store.add(TestPhoto.detailedJPEG, fileExtension: "jpg"))
        _ = try await service.image(edited, .init(), maxDimension: Self.previewPixels)

        let queued = thumbnails.map { url in
            Task(priority: priority) { _ = try? await service.image(url, .init(), maxDimension: Self.thumbnailPixels) }
        }
        try await Task.sleep(for: .milliseconds(20))
        let latency = try await Self.clock.measure {
            _ = try await service.image(edited, Self.sliderStep, maxDimension: Self.previewPixels)
        }
        let all = await Self.clock.measure { for task in queued { await task.value } }
        print(
            String(
                format: "Slider step behind %d queued 12 MP thumbnails at %@: %.0f ms (queue drained %.0f ms later)",
                Self.queuedThumbnails, "\(priority)", latency / .milliseconds(1), all / .milliseconds(1)))
    }

    @Test func sliderStepDuringA48MPExport() async throws {
        let library = TestLibrary()
        let service = library.renderService
        let raw48 = RAWDevelopChart.dng(.bayerRGGB, chart: RAWDevelopChart.chart(cell: 1008))
        let url = library.store.url(for: try await library.store.add(raw48, fileExtension: "dng"))
        _ = try await service.image(url, .init(), maxDimension: Self.previewPixels)
        let baseline = Footprint.current

        let peak = Footprint.Peak()
        let start = Self.clock.now
        let export = Task { () throws -> ContinuousClock.Instant in
            _ = try await service.export(url, .init(), format: .jpeg)
            return Self.clock.now
        }
        try await Task.sleep(for: .milliseconds(50))
        let stepAsked = Self.clock.now
        _ = try await service.image(url, Self.sliderStep, maxDimension: Self.previewPixels)
        let stepDone = Self.clock.now
        let exportDone = try await export.value
        let peakBytes = await peak.stop()
        print(
            String(
                format: "48 MP export %.0f ms; slider step asked at %.0f ms took %.0f ms, finishing %@ the export; peak footprint +%.2f GB",
                (exportDone - start) / .milliseconds(1), (stepAsked - start) / .milliseconds(1), (stepDone - stepAsked) / .milliseconds(1),
                stepDone > exportDone ? "after" : "before", Double(peakBytes - baseline) / 1e9))
    }

    @Test func relaunchedLibraryDevelops() async throws {
        let library = TestLibrary()
        let urls = try await Self.addRAWs(to: library)
        for url in urls { _ = try await library.renderService.image(url, .init(), maxDimension: Self.thumbnailPixels) }

        let relaunched = library.reopened().renderService
        let time = try await Self.clock.measure {
            for url in urls { _ = try await relaunched.image(url, .init(), maxDimension: Self.thumbnailPixels) }
        }
        print(
            String(
                format: "Relaunched library, %d 12 MP thumbnails: %d develops, %.0f ms", urls.count, await relaunched.developCount,
                time / .milliseconds(1)))
    }

    @Test func previewCacheAtA5KWindow() async throws {
        let library = TestLibrary()
        let service = library.renderService
        for url in try await Self.addRAWs(to: library).prefix(4) {
            for pixels in [5120, 4608, 4096] as [CGFloat] { _ = try await service.image(url, .init(), maxDimension: pixels) }
        }
        print(String(format: "Preview cache after 12 editor sizes at a 5K window: %.0f MB", Double(await service.cachedPreviewBytes) / 1e6))
    }
}

/// The process's physical footprint, as Xcode's memory gauge and the system's limits count it.
enum Footprint {
    static var current: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// The largest footprint seen every 5 ms until `stop`.
    final class Peak: Sendable {
        private let sampler: Task<Int, Never>

        init() {
            sampler = Task.detached {
                var peak = Footprint.current
                while !Task.isCancelled {
                    peak = max(peak, Footprint.current)
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return peak
            }
        }

        func stop() async -> Int {
            sampler.cancel()
            return await sampler.value
        }
    }
}
