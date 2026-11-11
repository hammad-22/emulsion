import Foundation

/// The visual regression report directory: `report.md`, `report.json`, `update-summary.md` and,
/// under `images/`, per-case actual / golden / diff images named like the goldens.
struct ReportFiles {
    let directory: URL
    var imagesDirectory: URL { directory.appending(path: "images") }

    private static let reportNames = ["report.md", "report.json", "update-summary.md"]
    private static let imageSuffixes = [".actual.png", ".golden.png", ".diff.png"]

    /// Creates the directory and removes the files a previous run wrote. Nothing else is touched:
    /// the directory may be one the user named.
    func prepare() throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let reports = Self.reportNames.map { directory.appending(path: $0) }
        let images = (files.enumerator(at: imagesDirectory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { url in Self.imageSuffixes.contains { url.lastPathComponent.hasSuffix($0) } }
        for url in reports + images where files.fileExists(atPath: url.path) && !url.hasDirectoryPath {
            try files.removeItem(at: url)
        }
    }

    func write(_ text: String, to name: String) throws {
        try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }

    func write(_ report: VisualRegression.Report) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appending(path: "report.json"))
        try write(markdown(report), to: "report.md")
    }

    /// `<case>.actual.png`, `<case>.golden.png` (if any) and `<case>.diff.png`, a ΔE00 heat map of
    /// `deltaE` (per pixel, present when the sizes match).
    func writeImages(_ name: String, actual: RegressionImage, golden: RegressionImage?, deltaE: [Double]?) throws {
        try save(actual, "\(name).actual.png")
        guard let golden else { return }
        try save(golden, "\(name).golden.png")
        guard let deltaE else { return }
        let scale = Double(UInt16.max) / VisualRegression.heatMapFullScale
        let heat = deltaE.map { SIMD3(repeating: UInt16(min(Double(UInt16.max), ($0 * scale).rounded()))) }
        try save(RegressionImage(width: actual.width, height: actual.height, pixels: heat), "\(name).diff.png")
    }

    private func save(_ image: RegressionImage, _ name: String) throws {
        let viewable = image.height == 1 ? image.enlarged(cell: VisualRegression.patchCellSize) : image
        try VisualRegression.write(viewable, to: imagesDirectory.appending(path: name))
    }

    private func markdown(_ report: VisualRegression.Report) -> String {
        let t = report.thresholds
        let header = [
            "### Visual regression: \(report.title)", "",
            "Thresholds (ΔE00): mean ≤ \(t.mean), p95 ≤ \(t.p95), max ≤ \(t.max); cases marked * use p99.9 ≤ \(t.max). "
                + "Host \(report.host), GPU \(report.gpu), \(report.os). "
                + String(format: "%d cases in %.1f s.", report.cases.count, report.seconds),
        ]
        return (header + Self.table(report.cases)).joined(separator: "\n") + "\n"
    }

    /// Printed and saved after an update: ΔE00 from the old golden to the new render.
    func updateSummary(_ outcomes: [VisualRegression.Outcome], title: String) -> String {
        let header = [
            "### Golden update: \(title)", "",
            "ΔE00 old golden → new render. Before / after / diff images (`<case>.golden.png`, `.actual.png`, `.diff.png`) for new and changed cases are in \(imagesDirectory.path).",
        ]
        let rewritten = outcomes.filter(\.rewritten).count
        let changed = outcomes.filter { $0.status == .new || $0.status == .changed }.count
        let footer = ["", "\(rewritten) of \(outcomes.count) goldens rewritten (\(changed) new or changed)."]
        return (header + Self.table(outcomes) + footer).joined(separator: "\n") + "\n"
    }

    private static func table(_ outcomes: [VisualRegression.Outcome]) -> [String] {
        ["", "| Case | Mean | p95 | p99.9 | Max | Status |", "| --- | ---: | ---: | ---: | ---: | --- |"]
            + outcomes.map { "| \($0.name)\($0.allowsIsolatedOutliers ? " *" : "") | \(columns($0.summary)) | \($0.status.rawValue) |" }
    }

    private static func columns(_ summary: ColorDifference.Summary?) -> String {
        guard let s = summary else { return "– | – | – | –" }
        return String(format: "%.4f | %.4f | %.4f | %.4f", s.mean, s.p95, s.p999, s.max)
    }
}
