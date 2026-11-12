import Foundation

extension URL {
    /// Whether a directory exists at this file URL (a file at the path doesn't count).
    var isExistingDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
