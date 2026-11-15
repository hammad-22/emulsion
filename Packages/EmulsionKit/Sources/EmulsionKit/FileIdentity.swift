import Foundation

/// A file's size and modification date: what changes when the file does.
struct FileIdentity: Codable, Equatable, Sendable {
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
