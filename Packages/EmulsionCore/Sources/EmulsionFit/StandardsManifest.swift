import Foundation

/// The committed provenance of the standards tables (`Resources/standards-manifest.json`): per file, which standard,
/// edition and table it transcribes, where from, and the SHA-256 the loader checks. The tables stay local (MOV-94).
struct StandardsManifest: Codable, Sendable, Equatable {
    static let supportedFormatVersion = 1

    let formatVersion: Int
    let files: [Entry]

    struct Entry: Codable, Sendable, Equatable {
        let file: String
        let standard: String
        let edition: String
        let table: String
        let source: String
        let sha256: String
    }

    static var bundledURL: URL? {
        Bundle.module.url(forResource: "standards-manifest", withExtension: "json")
    }

    static func bundled() throws(FitError) -> StandardsManifest {
        guard let url = bundledURL else { throw .missingFile("standards-manifest.json in the EmulsionFit bundle") }
        let manifest: StandardsManifest
        do {
            manifest = try JSONDecoder().decode(StandardsManifest.self, from: DigitizedStock.read(url))
        } catch let error as FitError {
            throw error
        } catch {
            throw .invalidManifest(file: url.path, reason: String(describing: error))
        }
        guard manifest.formatVersion == supportedFormatVersion else {
            throw .invalidManifest(file: url.path, reason: "unsupported formatVersion \(manifest.formatVersion).")
        }
        return manifest
    }

    func entry(_ file: String) -> Entry? { files.first { $0.file == file } }
}
