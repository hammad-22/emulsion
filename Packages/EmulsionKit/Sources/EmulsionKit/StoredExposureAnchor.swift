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

        /// Nil when the file can't be read.
        init?(_ file: URL) {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let byteCount = values.fileSize, let modified = values.contentModificationDate
            else { return nil }
            self.byteCount = byteCount
            self.modified = modified
        }
    }

    /// Whether this anchor still describes `file`.
    func matches(_ file: URL) -> Bool { Source(file) == source }
}
