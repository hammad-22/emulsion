import CryptoKit
import Foundation

/// One digitized datasheet chart, read from its CSV: a shared x column and one curve per remaining column.
/// An empty cell means the chart doesn't draw that curve at that x.
struct DigitizedChart: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case characteristic, spectralSensitivity, spectralDyeDensity

        /// The column layouts this tool reads; the first column is x.
        var acceptedHeaders: [[String]] {
            switch self {
            case .characteristic: [["log_exposure_lux_s", "red", "green", "blue"]]
            case .spectralSensitivity:
                [["wavelength_nm", "yellow_forming_layer", "magenta_forming_layer", "cyan_forming_layer"]]
            case .spectralDyeDensity:
                [
                    ["wavelength_nm", "yellow", "magenta", "cyan", "midscale_neutral", "minimum_density"],
                    ["wavelength_nm", "yellow", "magenta", "cyan", "visual_neutral"],
                ]
            }
        }
    }

    let kind: Kind
    /// What the manifest says about this chart: source page, conditions, traced extents, uncertainty.
    let entry: StockManifest.Chart
    let file: String
    let curves: [DigitizedCurve]
    /// SHA-256 (hex) of the CSV bytes, so a fit can name exactly what it used.
    let sha256: String

    init(kind: Kind, entry: StockManifest.Chart, file: String, data: Data) throws(FitError) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw .unreadableFile(file, reason: "not UTF-8 text.")
        }
        try self.init(kind: kind, entry: entry, file: file, text: text, sha256: Self.sha256(of: data))
    }

    /// - Parameter sha256: the digest of the file's bytes, already computed by the caller.
    init(kind: Kind, entry: StockManifest.Chart, file: String, text: String, sha256: String) throws(FitError) {
        self.kind = kind
        self.entry = entry
        self.file = file
        self.curves = try Self.parse(text, acceptedHeaders: kind.acceptedHeaders, file: file)
        self.sha256 = sha256
    }

    static func sha256(of data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func curve(named name: String) -> DigitizedCurve? { curves.first { $0.name == name } }

    /// The x values where every named curve has a sample, with those samples column by column.
    func aligned(_ names: [String]) -> (x: [Double], columns: [[Double]])? {
        let picked = names.compactMap(curve(named:))
        guard picked.count == names.count, let first = picked.first else { return nil }
        let lookups = picked.map { Dictionary(uniqueKeysWithValues: zip($0.x, $0.y)) }
        let x = first.x.filter { value in lookups.allSatisfy { $0[value] != nil } }
        return (x, lookups.map { lookup in x.compactMap { lookup[$0] } })
    }

    static func parse(_ text: String, acceptedHeaders: [[String]], file: String) throws(FitError) -> [DigitizedCurve] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        let header = lines.first.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) } ?? []
        guard acceptedHeaders.contains(header) else { throw .badHeader(file: file, expected: acceptedHeaders, found: header) }

        var x: [Double] = []
        var columns = Array(repeating: [(x: Double, y: Double)](), count: header.count - 1)
        for (index, line) in lines.enumerated().dropFirst() {
            let lineNumber = index + 1
            let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == header.count else {
                throw .wrongCellCount(file: file, line: lineNumber, expected: header.count, found: cells.count)
            }
            let rowX = try number(cells[0], file: file, line: lineNumber, column: header[0])
            if let previous = x.last, rowX <= previous {
                throw .nonAscendingX(file: file, line: lineNumber, previous: previous, value: rowX)
            }
            x.append(rowX)
            for (column, cell) in cells.enumerated().dropFirst() where !cell.isEmpty {
                columns[column - 1].append((rowX, try number(cell, file: file, line: lineNumber, column: header[column])))
            }
        }
        return try zip(header.dropFirst(), columns).map { name, samples throws(FitError) in
            guard !samples.isEmpty else { throw .emptyCurve(file: file, column: name) }
            return DigitizedCurve(name: name, x: samples.map(\.x), y: samples.map(\.y))
        }
    }

    private static func number(_ text: String, file: String, line: Int, column: String) throws(FitError) -> Double {
        guard let value = Double(text), value.isFinite else {
            throw .nonNumericCell(file: file, line: line, column: column, text: text)
        }
        return value
    }
}
