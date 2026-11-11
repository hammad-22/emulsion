import CoreImage
import Foundation
import Testing

@testable import EmulsionCore

/// Compares renders with goldens, writes the report and, on request, rewrites goldens. The
/// environment switches are read in one place, the Environment section.
enum VisualRegression {
    struct Thresholds: Codable, Sendable {
        let mean: Double
        let p95: Double
        let max: Double

        func accepts(_ s: ColorDifference.Summary) -> Bool { s.mean <= mean && s.p95 <= p95 && s.max <= max }
    }

    /// CIEDE2000 limits for every case. ΔE00 ≈ 1 is about one just-noticeable difference, so no
    /// pixel may move by a visible step (max) and the image as a whole must stay well under it
    /// (mean, p95). Measured noise (Apple M4 Max, `noiseFloorIsInsideTheThresholds`) is far below:
    /// the same case rendered twice is identical (0, grain included); a lazy vs materialized
    /// negative (gradient.default-look) differs by mean 0.008, p95 0.021, max 0.043; 16-bit
    /// quantisation of chart24.neutral by mean 0.0009, max 0.0023. Exposure +0.1 stop moves
    /// chart24.neutral by mean 1.27, max 1.85 and fails.
    static let thresholds = Thresholds(mean: 0.2, p95: 0.5, max: 1.0)
    /// ΔE00 shown as white in diff heat maps: twice the per-pixel limit.
    static let heatMapFullScale = 2.0
    /// Patch rows (one pixel high) are enlarged to cells this size in report images.
    static let patchCellSize = 16

    static let renderer = EmulsionTestCase.sharedRenderer

    static func render(_ scene: CIImage, _ adjustments: Adjustments, contract: InputContract = .sceneReferred) throws -> RegressionImage {
        let negative =
            contract == .displayReferred ? try renderer.developer.sceneFromDisplay(scene) : Negative(image: scene, contract: contract)
        return RegressionImage(rendering: try renderer.render(negative, adjustments))
    }

    /// Per-pixel CIEDE2000 and its summary.
    struct Comparison {
        let deltaE: [Double]
        let summary: ColorDifference.Summary
    }

    /// `nil` when the sizes differ.
    static func compare(_ golden: RegressionImage, _ actual: RegressionImage) -> Comparison? {
        guard golden.width == actual.width, golden.height == actual.height else { return nil }
        let deltaE = golden.deltaE(to: actual)
        return Comparison(deltaE: deltaE, summary: ColorDifference.Summary(deltaE))
    }

    // MARK: Environment

    /// Every switch the suite reads:
    /// - `EMULSION_UPDATE_GOLDENS`: `1` rewrites missing or failing goldens, `all` every golden.
    /// - `EMULSION_REGRESSION_IMAGES=all`: report images for every case, not only failures and updates.
    /// - `EMULSION_REGRESSION_REPORT`: report directory (default `.build/visual-regression`).
    /// - `CI`: any value; goldens are never accepted on CI.
    /// - `EMULSION_REGENERATE_SCENES`: folder with the CC0 sources; develops them into `Scenes/`.
    /// - `EMULSION_REFERENCE_SAMPLES`: folder of DNGs for the local tier.
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    enum UpdateMode: String, Codable, Sendable {
        case none, failing, all
    }

    static var updateMode: UpdateMode {
        switch environment["EMULSION_UPDATE_GOLDENS"] {
        case nil, "", "0": .none
        case "all": .all
        default: .failing
        }
    }
    static var writesAllImages: Bool { environment["EMULSION_REGRESSION_IMAGES"] == "all" }
    static var isCI: Bool { environment["CI"] != nil }
    static var reportDirectory: URL {
        environment["EMULSION_REGRESSION_REPORT"].map { URL(fileURLWithPath: $0) }
            ?? packageDirectory.appending(path: ".build/visual-regression")
    }
    static var sceneSourceDirectory: URL? { environment["EMULSION_REGENERATE_SCENES"].map { URL(fileURLWithPath: $0) } }
    static var referenceSamplesDirectory: URL? { environment["EMULSION_REFERENCE_SAMPLES"].map { URL(fileURLWithPath: $0) } }

    // MARK: Source tree

    /// This test target's folder in the source tree.
    static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let packageDirectory = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    static let sourceGoldens = testsDirectory.appending(path: "Goldens")
    static let sourceScenes = testsDirectory.appending(path: "Scenes")

    /// Where a suite's goldens are read from and written to, as `<directory>/<case name>.png`.
    struct Store: Sendable {
        let readDirectory: URL?
        let writeDirectory: URL

        /// Committed goldens: read from the test bundle, written into the source tree.
        static let repository = Store(
            readDirectory: Bundle.module.url(forResource: "Goldens", withExtension: nil), writeDirectory: sourceGoldens)

        /// Goldens kept next to local samples, outside git.
        static func local(_ directory: URL) -> Store { Store(readDirectory: directory, writeDirectory: directory) }

        func writeURL(_ name: String) -> URL { writeDirectory.appending(path: "\(name).png") }

        /// The golden, a failure if its file cannot be decoded, or `nil` if there is none.
        func golden(_ name: String) -> Result<RegressionImage, any Error>? {
            guard let url = readDirectory?.appending(path: "\(name).png"), let data = try? Data(contentsOf: url) else { return nil }
            return Result { try RegressionImage(pngData: data) }
        }
    }

    // MARK: Run

    struct Item {
        let name: String
        let render: () throws -> RegressionImage
    }

    struct Outcome: Codable {
        enum Status: String, Codable {
            case pass, fail, missing
            case new, changed, unchanged
            /// Checking the case threw (usually the render); recorded as an issue, never rewritten.
            case error

            /// Nothing to review: the golden passes, or an update left it as it was.
            var isClean: Bool { self == .pass || self == .unchanged }
        }
        let name: String
        let summary: ColorDifference.Summary?
        let status: Status
        /// The update wrote this case's golden, whether or not its pixels changed.
        var rewritten = false
    }

    struct Report: Codable {
        let title: String
        let thresholds: Thresholds
        let host: String
        let gpu: String
        let os: String
        let updateMode: UpdateMode
        let seconds: Double
        let cases: [Outcome]
    }

    /// Renders and checks every item, records one issue per failure (or rewrites goldens in an
    /// update), writes the report. `regenerate` is the command to accept an intended change,
    /// quoted in failure messages. The defaults come from the environment.
    static func run(
        _ title: String, _ items: [Item], store: Store, reportDirectory: URL, regenerate: String,
        mode: UpdateMode = VisualRegression.updateMode, isCI: Bool = VisualRegression.isCI,
        writesAllImages: Bool = VisualRegression.writesAllImages
    ) throws {
        if mode != .none && isCI {
            Issue.record("EMULSION_UPDATE_GOLDENS is set on CI: goldens are never accepted on CI. Regenerate locally and commit them.")
            return
        }
        let files = ReportFiles(directory: reportDirectory)
        try files.prepare()
        let clock = ContinuousClock()
        let start = clock.now
        var outcomes: [Outcome] = []
        for item in items {
            do {
                outcomes.append(
                    try check(item, store: store, mode: mode, files: files, writesAllImages: writesAllImages, regenerate: regenerate))
            } catch {
                Issue.record(error, "\(item.name): could not be checked")
                outcomes.append(Outcome(name: item.name, summary: nil, status: .error))
            }
        }
        let report = Report(
            title: title, thresholds: thresholds, host: Host.model, gpu: Host.gpu, os: ProcessInfo.processInfo.operatingSystemVersionString,
            updateMode: mode, seconds: (clock.now - start) / .seconds(1), cases: outcomes)
        try files.write(report)
        if mode != .none {
            let summary = files.updateSummary(outcomes, title: title)
            print(summary)
            try files.write(summary, to: "update-summary.md")
        }
    }

    private static func check(
        _ item: Item, store: Store, mode: UpdateMode, files: ReportFiles, writesAllImages: Bool, regenerate: String
    ) throws -> Outcome {
        let actual = try item.render()
        let stored = store.golden(item.name)
        let golden = try? stored?.get()
        let comparison = golden.flatMap { compare($0, actual) }
        let passes = comparison.map { thresholds.accepts($0.summary) } ?? false
        var outcome: Outcome
        switch mode {
        case .none:
            let status: Outcome.Status = stored == nil ? .missing : (passes ? .pass : .fail)
            outcome = Outcome(name: item.name, summary: comparison?.summary, status: status)
            if !passes {
                let unreadable = stored != nil && golden == nil
                Issue.record(
                    Comment(
                        rawValue: failureMessage(item.name, status, comparison?.summary, unreadable: unreadable, regenerate: regenerate)))
            }
        case .failing, .all:
            let rewrite = mode == .all || !passes
            if rewrite { try write(actual, to: store.writeURL(item.name)) }
            let status: Outcome.Status = stored == nil ? .new : (rewrite && golden != actual ? .changed : .unchanged)
            outcome = Outcome(name: item.name, summary: comparison?.summary, status: status)
            outcome.rewritten = rewrite
        }
        if !outcome.status.isClean || writesAllImages {
            try files.writeImages(item.name, actual: actual, golden: golden, deltaE: comparison?.deltaE)
        }
        return outcome
    }

    private static func failureMessage(
        _ name: String, _ status: Outcome.Status, _ summary: ColorDifference.Summary?, unreadable: Bool, regenerate: String
    ) -> String {
        let hint = "If the change is intended: \(regenerate)"
        if status == .missing { return "\(name): missing golden. \(hint)" }
        if unreadable { return "\(name): unreadable golden (not a 16-bit RGB PNG). \(hint)" }
        guard let s = summary else { return "\(name): golden and render differ in size. \(hint)" }
        let measured = String(format: "mean %.3f, p95 %.3f, max %.3f", s.mean, s.p95, s.max)
        return "\(name): ΔE00 \(measured) exceeds mean \(thresholds.mean), p95 \(thresholds.p95), max \(thresholds.max). \(hint)"
    }

    static func write(_ image: RegressionImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try image.pngData().write(to: url)
    }
}
