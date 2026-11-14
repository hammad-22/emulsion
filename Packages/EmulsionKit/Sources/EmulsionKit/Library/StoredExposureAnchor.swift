import Foundation

/// A RAW photo's exposure anchor (MOV-134), kept on its record so a relaunch develops with it
/// instead of measuring the file again (MOV-141). It belongs to the file it was measured from:
/// `source` identifies that file, and a file that no longer matches is measured again.
struct StoredExposureAnchor: Codable, Equatable, Sendable {
    let stops: Double
    let source: Source

    /// The original's size and modification date when the anchor was measured.
    struct Source: Codable, Equatable, Sendable {
        let byteCount: Int
        let modified: Date

        /// Nil when the file can't be read. Read from the file system each time: `URL.resourceValues`
        /// caches on the URL, which would hide a change.
        init?(_ file: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
                let byteCount = (attributes[.size] as? NSNumber)?.intValue, let modified = attributes[.modificationDate] as? Date
            else { return nil }
            self.byteCount = byteCount
            self.modified = modified
        }
    }
}
