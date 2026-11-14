import Foundation

/// A RAW photo's exposure anchor (MOV-134, MOV-141). See NOTES.md, "PhotoRecord and StoredExposureAnchor".
struct StoredExposureAnchor: Codable, Equatable, Sendable {
    let stops: Double
    let source: Source

    struct Source: Codable, Equatable, Sendable {
        let byteCount: Int
        let modified: Date

        /// Read from the file system each time: `URL.resourceValues` caches on the URL.
        init?(_ file: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
                let byteCount = (attributes[.size] as? NSNumber)?.intValue, let modified = attributes[.modificationDate] as? Date
            else { return nil }
            self.byteCount = byteCount
            self.modified = modified
        }
    }
}
