import Foundation

/// Why digitized stock data couldn't be loaded. Paths are as given, so messages point at the exact file.
enum FitError: LocalizedError, Equatable {
    case unknownStock(String, available: [String])
    case missingFile(String)
    case unreadableFile(String, reason: String)
    case invalidManifest(file: String, reason: String)
    case badHeader(file: String, expected: [[String]], found: [String])
    case wrongCellCount(file: String, line: Int, expected: Int, found: Int)
    case nonNumericCell(file: String, line: Int, column: String, text: String)
    case nonAscendingX(file: String, line: Int, previous: Double, value: Double)
    case emptyCurve(file: String, column: String)
    case checksumMismatch(file: String, expected: String, found: String)
    case invalidTable(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unknownStock(let id, let available):
            return "No digitized stock \"\(id)\". Available: \(available.isEmpty ? "none" : available.joined(separator: ", "))."
        case .missingFile(let path) where path.hasSuffix(".csv"):
            return """
                Missing file: \(path). Traced datasheet curves are not published in the repository: re-trace them from \
                the datasheet PDF with Tools/stock-digitizing/digitize.py into ~/\(DigitizedStock.defaultReferenceDataPath), \
                or set \(DigitizedStock.referenceDataEnvironmentVariable) to the output folder.
                """
        case .missingFile(let path):
            return "Missing file: \(path)."
        case .unreadableFile(let path, let reason):
            return "Can't read \(path): \(reason)"
        case .invalidManifest(let file, let reason):
            return "\(file): invalid manifest: \(reason)"
        case .badHeader(let file, let expected, let found):
            let options = expected.map { $0.joined(separator: ",") }.joined(separator: "\" or \"")
            return "\(file): header is \"\(found.joined(separator: ","))\", expected \"\(options)\"."
        case .wrongCellCount(let file, let line, let expected, let found):
            return "\(file):\(line): \(found) cells, expected \(expected)."
        case .nonNumericCell(let file, let line, let column, let text):
            return "\(file):\(line): \(column) is \"\(text)\", not a finite number."
        case .nonAscendingX(let file, let line, let previous, let value):
            return "\(file):\(line): x = \(value) does not ascend from the previous row's \(previous)."
        case .emptyCurve(let file, let column):
            return "\(file): column \(column) has no values."
        case .checksumMismatch(let file, let expected, let found):
            return "\(file): this is not the file its manifest describes: SHA-256 \(found), manifest pins \(expected)."
        case .invalidTable(let file, let reason):
            return "\(file): \(reason)"
        }
    }
}
