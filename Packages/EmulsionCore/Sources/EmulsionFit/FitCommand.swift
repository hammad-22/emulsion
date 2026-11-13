import Foundation

/// A parsed `emulsion-fit` command line. Options are `--name value` pairs, each at most once.
enum FitCommand: Equatable {
    case help
    case list(manifests: URL?, data: URL?)
    case check(manifests: URL?, data: URL?)
    case negative(NegativeOptions)
    case dyes(StockOptions)

    /// What `negative` and `dyes` share: the stock, where to write, and where its data and the standards tables are.
    struct StockOptions: Equatable {
        static let names: Set<String> = ["--stock", "--out", "--data", "--manifests", "--standards"]

        var stock: String
        var out: URL
        var manifests: URL?
        var data: URL?
        /// nil: `EMULSION_STANDARDS_DIR`, else `standards` beside the reference-data directory.
        var standards: URL?
    }

    struct NegativeOptions: Equatable {
        var shared: StockOptions
        var base: URL?
        var midGrayLogExposure: Double?
        var fitDate: String?
        var name: String?
        /// Also write the bundled default made from this fit here (`FittedStock.bundledDefault(from:)`).
        var bundledDefault: URL? = nil
    }

    /// `--manifests`, when the command takes it.
    var manifestsDirectory: URL? {
        switch self {
        case .help: nil
        case .list(let manifests, _), .check(let manifests, _): manifests
        case .negative(let options): options.shared.manifests
        case .dyes(let options): options.manifests
        }
    }

    /// `--data`, when the command takes it: the local reference data (traced CSVs).
    var dataDirectory: URL? {
        switch self {
        case .help: nil
        case .list(_, let data), .check(_, let data): data
        case .negative(let options): options.shared.data
        case .dyes(let options): options.data
        }
    }

    static let usage = """
        Usage:
          emulsion-fit list [--data <dir>] [--manifests <dir>]
          emulsion-fit check [--data <dir>] [--manifests <dir>]
          emulsion-fit negative --stock <id> --out <dir> [--standards <dir>] [--data <dir>] [--manifests <dir>]
                                [--base <stock.json>]
                                [--mid-gray-log-exposure <log10 lux-s>] [--fit-date YYYY-MM-DD] [--name <text>]
                                [--bundled-default <file>]
          emulsion-fit dyes --stock <id> --out <dir> [--standards <dir>] [--data <dir>] [--manifests <dir>]

        --data       reference data: the traced curve CSVs, <dir>/<stock>/<chart>.csv. They are not published:
                     re-trace them with Tools/stock-digitizing/digitize.py. Default: $\(DigitizedStock.referenceDataEnvironmentVariable),
                     else ~/\(DigitizedStock.defaultReferenceDataPath). check, negative and dyes need it;
                     list shows sample counts when it exists.
        --manifests  stock manifests (default: the bundled ones).
        --standards  standards tables (negative and dyes; not published). Default: $\(StandardsTables.environmentVariable),
                     else \(StandardsTables.siblingFolderName)/ beside the reference data.
        --bundled-default  negative, \(FittedStock.defaultSourceStock) only: also write the engine's bundled default
                     (named "\(FittedStock.bundledDefaultName)", no film brand in its provenance) to <file>.
        """

    init(arguments: [String]) throws(CommandLineError) {
        guard let command = arguments.first else { throw .missingCommand }
        let allowed: Set<String> =
            switch command {
            case "help", "--help", "-h": []
            case "list", "check": ["--data", "--manifests"]
            case "negative": StockOptions.names.union(["--base", "--mid-gray-log-exposure", "--fit-date", "--name", "--bundled-default"])
            case "dyes": StockOptions.names
            default: throw .unknownCommand(command)
            }
        let options = try Self.options(Array(arguments.dropFirst()), allowed: allowed, command: command)
        let manifests = options["--manifests"].map(Self.directory)
        let data = options["--data"].map(Self.directory)
        switch command {
        case "list": self = .list(manifests: manifests, data: data)
        case "check": self = .check(manifests: manifests, data: data)
        case "dyes": self = .dyes(try Self.stockOptions(options, command: command))
        case "negative":
            self = .negative(
                NegativeOptions(
                    shared: try Self.stockOptions(options, command: command), base: options["--base"].map { URL(filePath: $0) },
                    midGrayLogExposure: try options["--mid-gray-log-exposure"].map { text throws(CommandLineError) in
                        guard let value = Double(text), value.isFinite else {
                            throw .invalidNumber(option: "--mid-gray-log-exposure", text: text)
                        }
                        return value
                    },
                    fitDate: try options["--fit-date"].map { text throws(CommandLineError) in
                        guard Self.isCalendarDate(text) else { throw .invalidDate(option: "--fit-date", text: text) }
                        return text
                    },
                    name: options["--name"], bundledDefault: options["--bundled-default"].map { URL(filePath: $0) }))
        default: self = .help
        }
    }

    private static func directory(_ path: String) -> URL { URL(filePath: path, directoryHint: .isDirectory) }

    private static func stockOptions(_ options: [String: String], command: String) throws(CommandLineError) -> StockOptions {
        guard let stock = options["--stock"] else { throw .missingOption("--stock", command: command) }
        guard let out = options["--out"] else { throw .missingOption("--out", command: command) }
        return StockOptions(
            stock: stock, out: directory(out), manifests: options["--manifests"].map(directory), data: options["--data"].map(directory),
            standards: options["--standards"].map(directory))
    }

    private static func options(_ arguments: [String], allowed: Set<String>, command: String) throws(CommandLineError) -> [String: String] {
        var options: [String: String] = [:]
        var remaining = arguments[...]
        while let option = remaining.popFirst() {
            guard allowed.contains(option) else { throw .unknownOption(option, command: command) }
            guard let value = remaining.popFirst(), !value.hasPrefix("--") else { throw .missingValue(option: option) }
            guard options[option] == nil else { throw .duplicateOption(option) }
            options[option] = value
        }
        return options
    }

    /// `YYYY-MM-DD` naming a real day of the Gregorian calendar.
    private static func isCalendarDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else {
            return false
        }
        let numbers = parts.compactMap { Int($0) }
        let components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])
        return components.isValidDate(in: Calendar(identifier: .gregorian))
    }
}
