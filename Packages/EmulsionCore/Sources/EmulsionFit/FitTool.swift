import EmulsionCore
import Foundation

/// `emulsion-fit`: lists and checks the digitized datasheet data and fits the engine's negative curve to it.
public enum FitTool {
    /// Written into fitted stock files and reports as `tool`.
    static let version = "0.1.0"
    static var toolName: String { "emulsion-fit \(version)" }
    /// The stock a fit starts from unless `--base` names another.
    static let defaultBaseStock = "emulsion-default"
    /// sysexits.h EX_USAGE: the command line was wrong.
    static let usageExitCode: Int32 = 64
    static let failureExitCode: Int32 = 1

    /// Runs one command line (without the program name), printing to stdout and errors to stderr.
    public static func main(arguments: [String]) -> Int32 {
        let command: FitCommand
        do {
            command = try FitCommand(arguments: arguments)
        } catch {
            printError("\(error.errorDescription ?? "")\n\n\(FitCommand.usage)")
            return usageExitCode
        }
        do {
            let outcome = try perform(command)
            print(outcome.text, terminator: "")
            return outcome.succeeded ? 0 : failureExitCode
        } catch {
            printError(describe(error))
            return failureExitCode
        }
    }

    /// - Parameters:
    ///   - environment: `EMULSION_REFERENCE_DATA`, and `home` the home directory; passed in so tests don't depend on
    ///     the machine.
    static func perform(
        _ command: FitCommand,
        environment: String? = ProcessInfo.processInfo.environment[DigitizedStock.referenceDataEnvironmentVariable],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> (text: String, succeeded: Bool) {
        let manifests = { () throws(CommandLineError) -> URL in try manifestsDirectory(command.manifestsDirectory) }
        let resolved = DigitizedStock.referenceDataDirectory(flag: command.dataDirectory, environment: environment, home: home)
        if command.dataDirectory != nil { _ = try existingDirectory(resolved) }
        let referenceData = resolved.isExistingDirectory ? resolved : nil
        let requiredReferenceData = { () throws(CommandLineError) -> URL in
            guard let referenceData else { throw .noReferenceData(resolved.path) }
            return referenceData
        }
        switch command {
        case .help: return (FitCommand.usage + "\n", true)
        case .list: return list(try manifests(), referenceData: referenceData, tried: resolved)
        case .check: return check(try manifests(), referenceData: try requiredReferenceData())
        case .negative(let options): return (try negative(options, in: manifests(), referenceData: requiredReferenceData()), true)
        }
    }

    static func manifestsDirectory(_ given: URL?) throws(CommandLineError) -> URL {
        guard let directory = given ?? DigitizedStock.bundledManifestsDirectory else { throw .noBundledData }
        return try existingDirectory(directory)
    }

    private static func existingDirectory(_ directory: URL) throws(CommandLineError) -> URL {
        guard directory.isExistingDirectory else {
            throw .noSuchDirectory(directory.path)
        }
        return directory
    }

    // MARK: Commands

    /// Manifests alone give the stocks and curve names; reference data adds each curve's sample count. A stock that
    /// doesn't load is reported and the listing goes on; the command then fails, like `check`.
    /// - Parameter tried: where the reference data was looked for, named when it isn't there.
    private static func list(_ directory: URL, referenceData: URL?, tried: URL) -> (text: String, succeeded: Bool) {
        var lines: [String] = []
        var succeeded = true
        for id in DigitizedStock.availableIDs(in: directory) {
            do throws(FitError) {
                let manifest = try StockManifest.load(id: id, from: directory)
                lines.append("\(id): \(manifest.source.document), \(manifest.source.revision)")
                if let referenceData {
                    do throws(FitError) {
                        for chart in try DigitizedStock.load(id: id, from: directory, referenceData: referenceData).charts {
                            let curves = chart.curves.map { "\($0.name) (\($0.x.count))" }.joined(separator: ", ")
                            lines.append("  \(chart.kind.rawValue): \(curves)")
                        }
                    } catch {
                        lines.append("  FAILED to load: \(error.errorDescription ?? "")")
                        succeeded = false
                    }
                } else {
                    lines += manifestCurves(manifest)
                }
            } catch {
                lines.append("\(id): FAILED to load: \(error.errorDescription ?? "")")
                succeeded = false
            }
        }
        if lines.isEmpty { return ("No digitized stocks in \(directory.path).\n", true) }
        if referenceData == nil {
            lines.append(
                "(no reference data at \(tried.path): pass --data <dir> or set \(DigitizedStock.referenceDataEnvironmentVariable) "
                    + "for sample counts)")
        }
        return (lines.joined(separator: "\n") + "\n", succeeded)
    }

    /// Each chart's curve names from the manifest, in CSV column order.
    private static func manifestCurves(_ manifest: StockManifest) -> [String] {
        DigitizedChart.Kind.allCases.compactMap { kind in
            guard let chart = manifest.charts[kind.rawValue] else { return nil }
            let columns = kind.acceptedHeaders.flatMap { $0.dropFirst() }
            let curves = chart.curves.keys.sorted {
                (columns.firstIndex(of: $0) ?? .max, $0) < (columns.firstIndex(of: $1) ?? .max, $1)
            }
            return "  \(kind.rawValue): \(curves.joined(separator: ", "))"
        }
    }

    /// Fails only on data that doesn't load or doesn't pass the audit; the dye-sum misfit is a measurement, reported.
    private static func check(_ directory: URL, referenceData: URL) -> (text: String, succeeded: Bool) {
        var lines: [String] = []
        var succeeded = true
        let ids = DigitizedStock.availableIDs(in: directory)
        if ids.isEmpty {
            lines.append("No digitized stocks in \(directory.path).")
            succeeded = false
        }
        var dyeRows: [String] = []
        for id in ids {
            let stock: DigitizedStock
            do {
                stock = try DigitizedStock.load(id: id, from: directory, referenceData: referenceData)
            } catch {
                lines.append("\(id): FAILED to load: \(error.errorDescription ?? "")")
                succeeded = false
                continue
            }
            let findings = StockDataAudit.findings(for: stock)
            succeeded = succeeded && findings.isEmpty
            lines.append("\(id): \(findings.isEmpty ? "data OK" : "\(findings.count) audit findings")")
            lines += findings.map { "  \($0)" }
            let chart = stock.spectralDyeDensity
            let filmType = stock.manifest.filmType
            if let acceptance = DyeSumCheck.acceptance(chart, filmType: filmType) {
                dyeRows.append(dyeRow(id, "ACCEPTANCE", acceptance, isAcceptance: true))
                dyeRows += DyeSumCheck.diagnostics(chart, filmType: filmType).map {
                    dyeRow(id, "diagnostic: \($0.label)", $0.check, isAcceptance: false)
                }
            } else {
                dyeRows.append("\(id): no dye and neutral spectra to compare")
            }
        }
        lines += [
            "", "Dye sum vs neutral (residual = neutral − Σ a·dye; MOV-17 target max |residual| ≤ \(DyeSumCheck.targetMaxResidual) D)",
            "Acceptance: negatives compare neutral − minimum_density (dyes are drawn D-min subtracted); the print film compares",
            "its visual neutral over 400–700 nm. Diagnostic rows are reported, not judged.",
            "stock                    row                             nm        a_Y    a_M    a_C    RMS     mean r   max|r|  at nm  target",
        ]
        lines += dyeRows
        return (lines.joined(separator: "\n") + "\n", succeeded)
    }

    private static func dyeRow(_ id: String, _ label: String, _ check: DyeSumCheck, isAcceptance: Bool) -> String {
        let scales = check.scales.map { String(format: "%.3f", $0) }.joined(separator: "  ")
        let span = String(format: "%.0f–%.0f", check.wavelengths.first ?? .nan, check.wavelengths.last ?? .nan)
        let verdict = isAcceptance ? (check.meetsTarget ? "met" : "MISSED") : "—"
        return id.padding(toLength: 25, withPad: " ", startingAt: 0) + label.padding(toLength: 32, withPad: " ", startingAt: 0)
            + span.padding(toLength: 10, withPad: " ", startingAt: 0) + scales
            + String(format: "  %.4f  %+.4f  %.4f  %3.0f    ", check.rms, check.meanResidual, check.maxAbsResidual, check.wavelengthOfMax)
            + verdict
    }

    private static func negative(_ options: FitCommand.NegativeOptions, in directory: URL, referenceData: URL) throws -> String {
        let stock = try DigitizedStock.load(id: options.stock, from: directory, referenceData: referenceData)
        let report = try NegativeFitReport.fitting(stock, midGrayLogExposure: options.midGrayLogExposure, tool: toolName)
        let fitted = try FittedStock.make(base: baseStock(options.base), report: report, fitDate: options.fitDate, name: options.name)

        do {
            try FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
        } catch {
            throw NegativeFitError.writeFailed(path: options.out.path, reason: error.localizedDescription)
        }
        try write(fitted.encoded(), to: options.out.appending(path: "\(stock.id).stock.json"))
        try write(report.encoded(), to: options.out.appending(path: "\(stock.id).negative-fit.json"))
        try write(Data(report.plotTable().utf8), to: options.out.appending(path: "\(stock.id).negative-fit.csv"))
        return NegativeFitSummary.text(report)
            + "\nWrote \(stock.id).stock.json, .negative-fit.json, .negative-fit.csv to \(options.out.path)\n"
            + "The report and plot table contain traced samples: keep them out of the repository.\n"
    }

    private static func baseStock(_ url: URL?) throws -> FilmStock {
        guard let url else { return try FilmStock.bundled(named: defaultBaseStock) }
        do {
            return try FilmStock(data: Data(contentsOf: url))
        } catch {
            throw NegativeFitError.invalidBaseStock(path: url.path, reason: describe(error))
        }
    }

    private static func write(_ data: Data, to url: URL) throws(NegativeFitError) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    /// Description plus failure reason, so engine errors keep their developer detail here.
    static func describe(_ error: any Error) -> String {
        guard let error = error as? any LocalizedError else { return String(describing: error) }
        return [error.errorDescription, error.failureReason].compactMap { $0 }.joined(separator: " ")
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
