import Foundation

/// A command line `emulsion-fit` can't run.
enum CommandLineError: LocalizedError, Equatable {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(String, command: String)
    case missingValue(option: String)
    case duplicateOption(String)
    case missingOption(String, command: String)
    case invalidNumber(option: String, text: String)
    case invalidDate(option: String, text: String)
    case noSuchDirectory(String)
    case noBundledData
    case noReferenceData(String)

    var errorDescription: String? {
        switch self {
        case .missingCommand: return "No command given."
        case .unknownCommand(let command): return "Unknown command \"\(command)\"."
        case .unknownOption(let option, let command): return "\(command) doesn't take \(option)."
        case .missingValue(let option): return "\(option) needs a value."
        case .duplicateOption(let option): return "\(option) is given more than once."
        case .missingOption(let option, let command): return "\(command) needs \(option)."
        case .invalidNumber(let option, let text): return "\(option) must be a finite number, not \"\(text)\"."
        case .invalidDate(let option, let text): return "\(option) must be a date as YYYY-MM-DD, not \"\(text)\"."
        case .noSuchDirectory(let path): return "No directory at \(path)."
        case .noBundledData: return "This build has no bundled stock manifests; pass --manifests <dir>."
        case .noReferenceData(let path):
            return """
                No reference data at \(path): the traced curves are not published in the repository. Re-trace them from \
                the datasheet PDF with Tools/stock-digitizing/digitize.py, then pass --data <dir> or set \
                \(DigitizedStock.referenceDataEnvironmentVariable).
                """
        }
    }
}
