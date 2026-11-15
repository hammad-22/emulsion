import Foundation

extension URL {
    /// `flag`, else a non-empty `environment` value, else `fallback`.
    static func resolve(flag: URL?, environment: String?, fallback: URL) -> URL {
        if let flag { return flag }
        if let environment, !environment.isEmpty { return URL(filePath: environment, directoryHint: .isDirectory) }
        return fallback
    }

    var isExistingDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
