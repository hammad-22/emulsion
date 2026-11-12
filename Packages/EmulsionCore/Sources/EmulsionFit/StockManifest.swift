import Foundation

/// The fields of a digitized stock's `manifest.json` that this tool reads: the source document, the film type, and
/// per chart its file and that file's SHA-256, sampling grid, conditions, axis scales, traced extents, interpolated
/// stretches and digitizing uncertainty. Other keys are ignored.
struct StockManifest: Decodable, Sendable, Equatable {
    static let supportedFormatVersion = 1

    let formatVersion: Int
    let stock: String
    let filmType: FilmType
    let source: Source
    let charts: [String: Chart]

    enum FilmType: String, Decodable, Sendable {
        case cameraNegative, printFilm
    }

    /// Encoded into fit reports.
    struct Source: Codable, Sendable, Equatable {
        let publisher: String
        let document: String
        let title: String
        let revision: String
        let url: String
        let pdfSHA256: String
    }

    struct Chart: Decodable, Sendable, Equatable {
        let file: String
        /// SHA-256 (lowercase hex) of the traced CSV this entry describes.
        let sha256: String
        /// Spacing of the x grid the digitizer resampled onto: 0.05 log10 exposure or 5 nm.
        let gridStep: Double
        let conditions: String
        let xAxis: Axis
        let yAxis: Axis
        let uncertainty: Uncertainty
        let curves: [String: CurveExtent]
        /// The chart's camera-stop axis; only camera negatives have one.
        let cameraStops: CameraStops?
    }

    struct Axis: Decodable, Sendable, Equatable {
        let pixelsPerUnit: Double
    }

    /// One-sigma digitizing error per traced point, in data units. Encoded into fit reports.
    struct Uncertainty: Codable, Sendable, Equatable {
        let x: Double
        let y: Double
        let note: String
    }

    struct CurveExtent: Decodable, Sendable, Equatable {
        /// The traced x extent, before resampling onto the grid.
        let xRange: [Double]
        /// x spans bridged across a gap in the drawn line rather than traced.
        let interpolatedSpans: [[Double]]
        /// x spans where this curve shares one drawn line with another, so the channels can't be told apart.
        let sharedSpans: [[Double]]?

        /// Every span whose samples are not this curve's own trace.
        var untracedSpans: [[Double]] { interpolatedSpans + (sharedSpans ?? []) }
    }

    /// Numbers the checks and fits divide by or compare against, each named by its key path when unusable. Empty
    /// when all are usable; a zero grid step or pixel scale would otherwise make the audit pass vacuously.
    var problems: [String] {
        charts.sorted { $0.key < $1.key }.flatMap { name, chart in
            var problems: [String] = []
            func require(_ ok: Bool, _ field: String, _ rule: String) {
                if !ok { problems.append("charts.\(name).\(field) must be \(rule).") }
            }
            func isPositive(_ value: Double) -> Bool { value.isFinite && value > 0 }
            func isSpan(_ span: [Double]) -> Bool { span.count == 2 && span.allSatisfy(\.isFinite) && span[0] <= span[1] }
            func isSHA256(_ text: String) -> Bool { text.count == 64 && text.allSatisfy("0123456789abcdef".contains) }
            require(isSHA256(chart.sha256), "sha256", "64 lowercase hex characters")
            require(isPositive(chart.gridStep), "gridStep", "finite and above 0")
            require(isPositive(chart.xAxis.pixelsPerUnit), "xAxis.pixelsPerUnit", "finite and above 0")
            require(isPositive(chart.yAxis.pixelsPerUnit), "yAxis.pixelsPerUnit", "finite and above 0")
            require(chart.uncertainty.x.isFinite && chart.uncertainty.x >= 0, "uncertainty.x", "finite and at least 0")
            require(chart.uncertainty.y.isFinite && chart.uncertainty.y >= 0, "uncertainty.y", "finite and at least 0")
            for (curve, extent) in chart.curves.sorted(by: { $0.key < $1.key }) {
                require(
                    extent.xRange.count == 2 && extent.xRange.allSatisfy(\.isFinite) && extent.xRange[0] < extent.xRange[1],
                    "curves.\(curve).xRange", "two finite ascending values")
                require(extent.untracedSpans.allSatisfy(isSpan), "curves.\(curve) spans", "pairs of finite ascending values")
            }
            if let stops = chart.cameraStops {
                require(stops.stopZeroLogExposure.isFinite, "cameraStops.stopZeroLogExposure", "finite")
            }
            return problems
        }
    }

    struct CameraStops: Decodable, Sendable, Equatable {
        /// Where camera stop 0 (normal exposure) sits on the chart's log10 exposure axis.
        let stopZeroLogExposure: Double
    }
}

extension StockManifest {
    static func url(in stockDirectory: URL) -> URL { stockDirectory.appending(path: "manifest.json") }

    /// The manifest of stock `id` under `directory`, validated; needs no traced curves.
    static func load(id: String, from directory: URL) throws(FitError) -> StockManifest {
        let stockDirectory = directory.appending(path: id, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url(in: stockDirectory).path) else {
            throw .unknownStock(id, available: DigitizedStock.availableIDs(in: directory))
        }
        return try StockManifest(directory: stockDirectory)
    }

    /// Reads `directory/manifest.json` and checks its format version, that it names its directory's stock, and
    /// that it has no `problems`.
    init(directory: URL) throws(FitError) {
        let file = Self.url(in: directory)
        do {
            self = try JSONDecoder().decode(StockManifest.self, from: DigitizedStock.read(file))
        } catch let error as FitError {
            throw error
        } catch {
            throw .invalidManifest(file: file.path, reason: String(describing: error))
        }
        guard formatVersion == Self.supportedFormatVersion else {
            throw .invalidManifest(file: file.path, reason: "unsupported formatVersion \(formatVersion).")
        }
        guard stock == directory.lastPathComponent else {
            throw .invalidManifest(
                file: file.path, reason: "stock is \"\(stock)\" but the directory is \"\(directory.lastPathComponent)\".")
        }
        guard problems.isEmpty else {
            throw .invalidManifest(file: file.path, reason: problems.joined(separator: " "))
        }
    }
}
