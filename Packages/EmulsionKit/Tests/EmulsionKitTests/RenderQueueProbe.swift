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

    /// Thumbnails at the editor's priority, then at the library's lower one (`RenderedPhoto`).
    @Test(arguments: [TaskPriority.userInitiated, .utility])
    func sliderStepBehindQueuedThumbnails(priority: TaskPriority) async throws {
        let library = TestLibrary()
        let service = library.renderService
        var thumbnails: [URL] = []
        for _ in 0..<Self.queuedThumbnails {
            thumbnails.append(library.store.url(for: try await library.store.add(Self.raw12, fileExtension: "dng")))
        }
        let edited = library.store.url(for: try await library.store.add(TestPhoto.detailedJPEG, fileExtension: "jpg"))
        _ = try await service.image(edited, .init(), maxDimension: Self.previewPixels)

        let queued = thumbnails.map { url in
            Task(priority: priority) { _ = try? await service.image(url, .init(), maxDimension: Self.thumbnailPixels) }
        }
        try await Task.sleep(for: .milliseconds(20))
        var step = Adjustments()
        step.warmth = 0.3
        let latency = try await Self.clock.measure { _ = try await service.image(edited, step, maxDimension: Self.previewPixels) }
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
        let export = Task(priority: .utility) { try await service.export(url, .init(), format: .jpeg) }
        try await Task.sleep(for: .milliseconds(50))
        var step = Adjustments()
        step.warmth = 0.3
        let latency = try await Self.clock.measure { _ = try await service.image(url, step, maxDimension: Self.previewPixels) }
        let exportTime = try await Self.clock.measure { _ = try await export.value }
        let peakBytes = await peak.stop()
        print(
            String(
                format: "Slider step during a 48 MP export: %.0f ms; export finished %.0f ms later; peak footprint +%.2f GB",
                latency / .milliseconds(1), exportTime / .milliseconds(1), Double(peakBytes - baseline) / 1e9))
    }

    @Test func relaunchedLibraryDevelops() async throws {
        let library = TestLibrary()
        var urls: [URL] = []
        for _ in 0..<Self.queuedThumbnails {
            urls.append(library.store.url(for: try await library.store.add(Self.raw12, fileExtension: "dng")))
        }
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
        var bytes = 0
        for _ in 0..<4 {
            let url = library.store.url(for: try await library.store.add(Self.raw12, fileExtension: "dng"))
            for pixels in [5120, 4608, 4096] as [CGFloat] {
                let image = try await service.image(url, .init(), maxDimension: pixels)
                bytes += image.width * image.height * 8
            }
        }
        print(String(format: "Preview cache after 12 editor sizes at a 5K window: about %.0f MB", Double(bytes) / 1e6))
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
