import Foundation
import Testing

/// Grain as the CIELAB L* residual r = L*(with grain) − L*(same render without grain), winsorized
/// at 6 robust σ: its mean, standard deviation and the correlation of horizontally adjacent
/// pixels (grain size). Seeded grain is identical on one GPU but not pixel for pixel across GPUs:
/// GitHub's runner gave a few isolated pixels a grain value several times larger than any on an
/// M4 Max (cause not investigated). So the visual regression suite compares these statistics with
/// `Goldens/grain-statistics.json` instead of grain goldens.
struct GrainStatistics: Codable, Equatable, Sendable {
    /// L* units.
    let mean: Double
    /// L* units, population standard deviation.
    let sd: Double
    /// Pearson correlation of r(x, y) with r(x + 1, y).
    let neighbourCorrelation: Double

    init(mean: Double, sd: Double, neighbourCorrelation: Double) {
        (self.mean, self.sd, self.neighbourCorrelation) = (mean, sd, neighbourCorrelation)
    }

    init(grainy: RegressionImage, clean: RegressionImage) {
        precondition(grainy.width == clean.width && grainy.height == clean.height)
        let raw = zip(grainy.encoded, clean.encoded).map { grainy, clean in
            ColorDifference.lab(fromDisplayP3: grainy).x - ColorDifference.lab(fromDisplayP3: clean).x
        }
        let width = grainy.width
        let residual = Self.winsorized(raw)
        let pairs = residual.indices.filter { ($0 + 1) % width != 0 }
        mean = Self.mean(residual)
        sd = Self.standardDeviation(residual)
        neighbourCorrelation = Self.correlation(pairs.map { residual[$0] }, pairs.map { residual[$0 + 1] })
    }

    // MARK: Tolerances

    /// sd may move by 2% of the reference. Measured grain is small (sd 0.10–0.27 L*, no residual
    /// beyond 1.3 L*), so the ~15 isolated pixels of 43,200 that GitHub's runner rendered up to
    /// 4.67 ΔE00 off would move a plain sd by 6–10%. Winsorizing at `winsorLimit` caps each at 6σ,
    /// so 15 such pixels add at most 15 · 36σ² / 43,200 to the variance: sd +0.62% (measured
    /// +0.64% with 15 pixels moved ±5.9 L*, `isolatedFlippedPixelsStayInsideTheTolerances`);
    /// about 48 would be needed to fail. 5% less grain moves sd by 5% and fails
    /// (`aSmallGrainChangeFailsAndASeedChangePasses`).
    static let sdRelativeTolerance = 0.02
    /// L* units. Measured means are within ±0.005 of zero; 15 capped pixels shift it by < 0.001.
    static let meanTolerance = 0.02
    /// Correlation units. Each flipped pixel enters two of ~43,000 pairs; 15 moved it by 0.004.
    static let neighbourCorrelationTolerance = 0.02

    /// The statistics outside tolerance of `reference`, by name; empty when all match.
    func mismatches(against reference: GrainStatistics) -> [String] {
        var names: [String] = []
        if abs(mean - reference.mean) > Self.meanTolerance { names.append("mean") }
        if abs(sd - reference.sd) > Self.sdRelativeTolerance * reference.sd { names.append("sd") }
        if abs(neighbourCorrelation - reference.neighbourCorrelation) > Self.neighbourCorrelationTolerance {
            names.append("neighbourCorrelation")
        }
        return names
    }

    /// Rounded to 6 decimals, the precision the reference file keeps.
    var rounded: GrainStatistics {
        func round6(_ v: Double) -> Double {
            let r = (v * 1e6).rounded() / 1e6
            return r == 0 ? 0 : r
        }
        return GrainStatistics(mean: round6(mean), sd: round6(sd), neighbourCorrelation: round6(neighbourCorrelation))
    }

    /// Residuals beyond `winsorLimit` robust standard deviations of the median are set to that
    /// limit, so a handful of outlying pixels cannot dominate the moments.
    static func winsorized(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return values }
        let median = sorted[sorted.count / 2]
        let deviations = values.map { abs($0 - median) }.sorted()
        let limit = winsorLimit * madToStandardDeviation * deviations[deviations.count / 2]
        guard limit > 0 else { return values }
        return values.map { min(median + limit, max(median - limit, $0)) }
    }

    /// Robust standard deviations from the median beyond which a residual is clipped. A Gaussian
    /// value lies beyond 6σ with probability 2·10⁻⁹, so genuine grain is not clipped.
    static let winsorLimit = 6.0
    /// σ = 1.4826 · median absolute deviation for a normal distribution.
    private static let madToStandardDeviation = 1.4826

    private static func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    private static func standardDeviation(_ values: [Double]) -> Double {
        let m = mean(values)
        return mean(values.map { ($0 - m) * ($0 - m) }).squareRoot()
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let (meanA, meanB) = (mean(a), mean(b))
        let covariance = mean(zip(a, b).map { ($0 - meanA) * ($1 - meanB) })
        let spread = standardDeviation(a) * standardDeviation(b)
        return spread > 0 ? covariance / spread : 0
    }

    // MARK: References

    typealias References = [String: GrainStatistics]
    static let referenceFileName = "grain-statistics.json"
    static let reportFileName = "grain-statistics.md"

    /// The stored references, or `nil` when there is no file.
    static func references(in directory: URL?) throws -> References? {
        guard let url = directory?.appending(path: referenceFileName), let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(References.self, from: data)
    }

    static func write(_ references: References, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(references).write(to: directory.appending(path: referenceFileName))
    }

    // MARK: Run

    struct Item {
        let name: String
        let measure: () throws -> GrainStatistics
    }

    struct Row {
        let name: String
        let reference: GrainStatistics?
        let measured: GrainStatistics?
        let status: VisualRegression.Outcome.Status
    }

    /// Measures every item and checks it against the references in `store` (or, in an update,
    /// rewrites missing and failing entries, or all with `.all`, and drops entries no item
    /// measures). Writes `grain-statistics.md` to `reportDirectory` in every mode.
    static func run(
        _ items: [Item], store: VisualRegression.Store, reportDirectory: URL, regenerate: String,
        mode: VisualRegression.UpdateMode = VisualRegression.updateMode, isCI: Bool = VisualRegression.isCI
    ) throws {
        guard !VisualRegression.refusesUpdate(mode: mode, isCI: isCI) else { return }
        let stored: References
        do {
            stored = try references(in: store.readDirectory) ?? [:]
        } catch {
            if mode == .none { Issue.record(error, "\(referenceFileName) is unreadable. If the change is intended: \(regenerate)") }
            stored = [:]
        }
        let names = Set(items.map(\.name))
        var updated = stored.filter { names.contains($0.key) }
        var rows: [Row] = []
        for item in items {
            let reference = stored[item.name]
            let measured: GrainStatistics
            do {
                measured = try item.measure()
            } catch {
                Issue.record(error, "\(item.name): grain could not be measured")
                rows.append(Row(name: item.name, reference: reference, measured: nil, status: .error))
                continue
            }
            let mismatches = reference.map(measured.mismatches(against:))
            let passes = mismatches?.isEmpty ?? false
            switch mode {
            case .none:
                rows.append(
                    Row(
                        name: item.name, reference: reference, measured: measured,
                        status: reference == nil ? .missing : (passes ? .pass : .fail)))
                if !passes {
                    let what = mismatches.map { "\($0.joined(separator: ", ")) outside tolerance" } ?? "no reference"
                    Issue.record(
                        "\(item.name): grain statistics \(what) (measured \(measured), reference \(reference.map { "\($0)" } ?? "none")). If the change is intended: \(regenerate)"
                    )
                }
            case .failing, .all:
                let rewrite = mode == .all || !passes
                if rewrite { updated[item.name] = measured.rounded }
                let status: VisualRegression.Outcome.Status =
                    reference == nil ? .new : (rewrite && reference != measured.rounded ? .changed : .unchanged)
                rows.append(Row(name: item.name, reference: reference, measured: measured, status: status))
            }
        }
        if mode != .none && updated != stored { try write(updated, to: store.writeDirectory) }
        let removed = stored.keys.filter { !names.contains($0) }.sorted()
        let table = markdown(rows, removed: mode == .none ? [] : removed, mode: mode)
        if mode != .none { print(table) }
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        try table.write(to: reportDirectory.appending(path: reportFileName), atomically: true, encoding: .utf8)
    }

    private static func markdown(_ rows: [Row], removed: [String], mode: VisualRegression.UpdateMode) -> String {
        let title = mode == .none ? "### Grain statistics" : "### Grain statistics update (old reference → new measurement)"
        let tolerances = String(
            format: "L* residual with vs without grain. Tolerances: mean ±%.2f L*, sd ±%.0f%%, neighbour correlation ±%.2f.",
            meanTolerance, sdRelativeTolerance * 100, neighbourCorrelationTolerance)
        let header = [
            title, "", tolerances, "",
            "| Case | Ref. mean | Ref. sd | Ref. corr. | Mean | sd | Corr. | Status |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
        let lines = rows.map { "| \($0.name) | \(columns($0.reference)) | \(columns($0.measured)) | \($0.status.rawValue) |" }
        let footer = removed.isEmpty ? [] : ["", "Removed entries with no grain case: \(removed.joined(separator: ", "))."]
        return (header + lines + footer).joined(separator: "\n") + "\n"
    }

    private static func columns(_ s: GrainStatistics?) -> String {
        guard let s else { return "– | – | –" }
        return String(format: "%.4f | %.4f | %.4f", s.mean, s.sd, s.neighbourCorrelation)
    }
}
