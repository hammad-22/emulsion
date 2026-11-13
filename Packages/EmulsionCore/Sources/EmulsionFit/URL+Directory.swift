import Foundation

extension URL {
    /// A directory given by `flag` if set, else by a non-empty `environment` value, else `fallback`.
    static func resolve(flag: URL?, environment: String?, fallback: URL) -> URL {
        if let flag { return flag }
        if let environment, !environment.isEmpty { return URL(filePath: environment, directoryHint: .isDirectory) }
        return fallback
    }

    /// Whether a directory exists at this file URL (a file at the path doesn't count).
    var isExistingDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
