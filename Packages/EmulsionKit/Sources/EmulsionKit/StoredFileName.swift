import Foundation

/// The names Emulsion stores its files under. They are on users' disks: never rename one.
enum StoredFileName {
    static let appFolder = "Emulsion"
    static let libraryIndex = "library.json"
    static let unreadableLibraryIndexPrefix = "library-unreadable-"
    static let importStagingPrefix = ".import-"
    static let recipes = "recipes.json"

    static var appFolderURL: URL { URL.applicationSupportDirectory.appending(path: appFolder, directoryHint: .isDirectory) }
}
