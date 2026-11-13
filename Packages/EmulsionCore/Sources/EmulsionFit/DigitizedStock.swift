import Foundation

/// A stock's digitized datasheet charts and their manifest, validated on load. The manifest comes from a manifests
/// directory (`<id>/manifest.json`); the traced CSVs, which are not published, from the local reference-data directory
/// (`<id>/<chart file>`), and each must match the SHA-256 its manifest pins.
struct DigitizedStock: Sendable, Equatable {
    let id: String
    let manifest: StockManifest
    let characteristic: DigitizedChart
    let spectralSensitivity: DigitizedChart
    let spectralDyeDensity: DigitizedChart

    /// The stock manifests bundled with this tool. The curves they describe are not bundled (see `referenceDataDirectory`).
    static var bundledManifestsDirectory: URL? { Bundle.module.url(forResource: "StockData", withExtension: nil) }

    static let referenceDataEnvironmentVariable = "EMULSION_REFERENCE_DATA"
    /// Where the reference data lives when the environment variable is unset, relative to the home directory.
    static let defaultReferenceDataPath = "Documents/Emulsion Research/datasheet-tracings"

    /// The local folder of traced CSVs (`<id>/<chart file>`), outside the repository; it may not exist.
    static var referenceDataDirectory: URL {
        referenceDataDirectory(
            flag: nil, environment: ProcessInfo.processInfo.environment[referenceDataEnvironmentVariable],
            home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `flag` if given, else a non-empty `environment`, else `defaultReferenceDataPath` under `home`.
    static func referenceDataDirectory(flag: URL?, environment: String?, home: URL) -> URL {
        URL.resolve(
            flag: flag, environment: environment, fallback: home.appending(path: defaultReferenceDataPath, directoryHint: .isDirectory))
    }

    /// Every stock directory under `directory` that holds a manifest, sorted by id.
    static func availableIDs(in directory: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.filter { FileManager.default.fileExists(atPath: StockManifest.url(in: directory.appending(path: $0)).path) }
            .sorted()
    }

    /// Loads stock `id`'s manifest from `directory` and its charts from `referenceData/<id>/`. Each CSV's SHA-256 is
    /// checked against the manifest before it is parsed, so a different file is reported as a mismatch.
    static func load(id: String, from directory: URL, referenceData: URL) throws(FitError) -> DigitizedStock {
        let manifest = try StockManifest.load(id: id, from: directory)
        let manifestFile = StockManifest.url(in: directory.appending(path: id, directoryHint: .isDirectory))
        let stockData = referenceData.appending(path: id, directoryHint: .isDirectory)
        func chart(_ kind: DigitizedChart.Kind) throws(FitError) -> DigitizedChart {
            guard let entry = manifest.charts[kind.rawValue] else {
                throw .invalidManifest(file: manifestFile.path, reason: "no \(kind.rawValue) chart.")
            }
            let file = stockData.appending(path: entry.file)
            let text = try readVerifiedText(file, sha256: entry.sha256)
            return try DigitizedChart(kind: kind, entry: entry, file: file.path, text: text, sha256: entry.sha256)
        }
        return try DigitizedStock(
            id: id, manifest: manifest, characteristic: chart(.characteristic), spectralSensitivity: chart(.spectralSensitivity),
            spectralDyeDensity: chart(.spectralDyeDensity))
    }

    var charts: [DigitizedChart] { [characteristic, spectralSensitivity, spectralDyeDensity] }

    static func read(_ url: URL) throws(FitError) -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw .missingFile(url.path) }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .unreadableFile(url.path, reason: error.localizedDescription)
        }
    }

    /// Reads `url`, checks its SHA-256 against the `expected` digest a manifest pins, and decodes it as UTF-8 text.
    static func readVerifiedText(_ url: URL, sha256 expected: String) throws(FitError) -> String {
        let data = try read(url)
        let digest = DigitizedChart.sha256(of: data)
        guard digest == expected else { throw .checksumMismatch(file: url.path, expected: expected, found: digest) }
        guard let text = String(data: data, encoding: .utf8) else { throw .unreadableFile(url.path, reason: "not UTF-8 text.") }
        return text
    }
}
