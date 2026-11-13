import Foundation

/// The density definitions the dye-set checks integrate through, read from a local directory of standards tables
/// (`--standards`, see `directory(flag:environment:referenceData:)`); each file must match the SHA-256 in
/// `StandardsManifest`.
///
/// - Status M: ISO 5-3:1995 Table 4 tabulates log10 spectral products, 5.000 at the peak, at 10 nm. Interpolated
///   linearly in log10 and extrapolated in log10 with the table's slopes below and above each channel's span.
/// - APD: SMPTE ST 2065-2:2020 element a, at 2 nm, linear between samples, zero outside.
/// - RP 180: SMPTE RP 180-1999 Table 1, at 10 nm, linear between samples, zero outside.
struct StandardsTables: Sendable, Equatable {
    static let statusMFile = "iso5-3-1995-status-m.csv"
    static let statusMSlopesFile = "iso5-3-1995-status-m.slopes.json"
    static let academyPrintingDensityFile = "st2065-2a-2020.csv"
    static let rp180File = "rp180-1999-table1.csv"
    static let files = [statusMFile, statusMSlopesFile, academyPrintingDensityFile, rp180File]
    static let environmentVariable = "EMULSION_STANDARDS_DIR"
    /// The default folder, beside the reference data (`~/Documents/Emulsion Research/standards` by default).
    static let siblingFolderName = "standards"
    /// ISO 5-3 Table 4 normalizes each channel's log10 spectral product to this at its peak.
    static let statusMLogPeak = 5.0

    let statusM: SpectralResponsivities
    let academyPrintingDensity: SpectralResponsivities
    let rp180: SpectralResponsivities
    /// The manifest entries of the files read, in `files` order.
    let provenance: [StandardsManifest.Entry]

    /// The standards tables directory when no flag is given; it may not exist.
    static var defaultDirectory: URL {
        directory(
            flag: nil, environment: ProcessInfo.processInfo.environment[environmentVariable],
            referenceData: DigitizedStock.referenceDataDirectory)
    }

    /// `flag` if given, else a non-empty `environment`, else `siblingFolderName` beside the resolved `referenceData`.
    static func directory(flag: URL?, environment: String?, referenceData: URL) -> URL {
        URL.resolve(
            flag: flag, environment: environment,
            fallback: referenceData.deletingLastPathComponent().appending(path: siblingFolderName, directoryHint: .isDirectory))
    }

    static func load(
        from directory: URL, manifest: StandardsManifest? = nil, grid: [Double] = SpectralResponsivities.grid
    ) throws(FitError) -> StandardsTables {
        let manifest = if let manifest { manifest } else { try StandardsManifest.bundled() }
        var texts: [String: String] = [:]
        var provenance: [StandardsManifest.Entry] = []
        for name in files {
            guard let entry = manifest.entry(name) else {
                throw .invalidManifest(file: "standards-manifest.json", reason: "no entry for \(name).")
            }
            let text = try DigitizedStock.readVerifiedText(directory.appending(path: name), sha256: entry.sha256)
            texts[name] = text.replacingOccurrences(of: "\r\n", with: "\n")
            provenance.append(entry)
        }
        func path(_ name: String) -> String { directory.appending(path: name).path }
        return StandardsTables(
            statusM: try statusM(
                csv: texts[statusMFile] ?? "", slopesJSON: texts[statusMSlopesFile] ?? "", file: path(statusMFile), grid: grid),
            academyPrintingDensity: try academyPrintingDensity(
                csv: texts[academyPrintingDensityFile] ?? "", file: path(academyPrintingDensityFile), grid: grid),
            rp180: try rp180(csv: texts[rp180File] ?? "", file: path(rp180File), grid: grid),
            provenance: provenance)
    }

    /// Per channel, log10 slope per nm below and above the tabulated span.
    struct StatusMSlopes: Decodable, Sendable, Equatable {
        struct Pair: Decodable, Sendable, Equatable {
            let below: Double
            let above: Double
        }
        let red: Pair
        let green: Pair
        let blue: Pair
    }

    static func statusM(csv: String, slopesJSON: String, file: String, grid: [Double]) throws(FitError) -> SpectralResponsivities {
        let slopes: StatusMSlopes
        do {
            slopes = try JSONDecoder().decode(StatusMSlopes.self, from: Data(slopesJSON.utf8))
        } catch {
            throw .invalidTable(file: file, reason: "slopes: \(error)")
        }
        let curves = try DigitizedChart.parse(csv, acceptedHeaders: [["wavelength_nm", "blue", "green", "red"]], file: file)
        let pairs = [slopes.red, slopes.green, slopes.blue]
        let channels = zip(SpectralResponsivities.Channel.allCases, pairs).map { channel, pair in
            let curve = curves.first { $0.name == channel.rawValue } ?? DigitizedCurve(name: channel.rawValue, x: [], y: [])
            return curve.resampled(onto: grid, edge: .slopes(below: pair.below, above: pair.above)).map { pow(10, $0 - statusMLogPeak) }
        }
        return SpectralResponsivities(name: "Status M (ISO 5-3:1995)", wavelengths: grid, channels: channels)
    }

    /// The file has title rows before its ` nm,Red,Green,Blue` header.
    static func academyPrintingDensity(csv: String, file: String, grid: [Double]) throws(FitError) -> SpectralResponsivities {
        let header = ["nm", "Red", "Green", "Blue"]
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        guard
            let headerLine = lines.firstIndex(where: { line in
                line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } == header
            })
        else { throw .invalidTable(file: file, reason: "no \"\(header.joined(separator: ","))\" header row.") }
        let table = ([header.joined(separator: ",")] + lines[(headerLine + 1)...].map(String.init)).joined(separator: "\n")
        return try linear(table, header: header, name: "APD (SMPTE ST 2065-2:2020)", file: file, grid: grid)
    }

    static func rp180(csv: String, file: String, grid: [Double]) throws(FitError) -> SpectralResponsivities {
        try linear(
            csv, header: ["wavelength_nm", "red", "green", "blue"], name: "Printing density (SMPTE RP 180-1999)", file: file, grid: grid)
    }

    private static func linear(_ csv: String, header: [String], name: String, file: String, grid: [Double]) throws(FitError)
        -> SpectralResponsivities
    {
        let curves = try DigitizedChart.parse(csv, acceptedHeaders: [header], file: file)
        return SpectralResponsivities(name: name, wavelengths: grid, channels: curves.map { $0.resampled(onto: grid, edge: .zero) })
    }
}
