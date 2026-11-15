import Foundation

/// The fields of a stock's `manifest.json` this tool reads (docs/CONSTANTS.md).
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
        /// SHA-256 (lowercase hex) of the traced CSV.
        let sha256: String
        /// Digitizer grid: 0.05 log10 exposure or 5 nm.
        let gridStep: Double
        let conditions: String
        let xAxis: Axis
        let yAxis: Axis
        let uncertainty: Uncertainty
        let curves: [String: CurveExtent]
        let cameraStops: CameraStops?
    }

    struct Axis: Decodable, Sendable, Equatable {
        let pixelsPerUnit: Double
    }

    /// One-sigma digitizing error per traced point, data units.
    struct Uncertainty: Codable, Sendable, Equatable {
        let x: Double
        let y: Double
        let note: String
    }

    struct CurveExtent: Decodable, Sendable, Equatable {
        let xRange: [Double]
        /// x spans bridged across a gap in the drawn line.
        let interpolatedSpans: [[Double]]
        /// x spans where this curve shares one drawn line with another.
        let sharedSpans: [[Double]]?

        var untracedSpans: [[Double]] { interpolatedSpans + (sharedSpans ?? []) }
    }

    /// Unusable divisors by key path; a zero step would make the audit pass vacuously.
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
        /// log10 exposure of camera stop 0 (normal exposure).
        let stopZeroLogExposure: Double
    }
}

extension StockManifest {
    static func url(in stockDirectory: URL) -> URL { stockDirectory.appending(path: "manifest.json") }

    static func load(id: String, from directory: URL) throws(FitError) -> StockManifest {
        let stockDirectory = directory.appending(path: id, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url(in: stockDirectory).path) else {
            throw .unknownStock(id, available: DigitizedStock.availableIDs(in: directory))
        }
        return try StockManifest(directory: stockDirectory)
    }

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
