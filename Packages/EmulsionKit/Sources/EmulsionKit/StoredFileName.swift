import Foundation

/// The names Emulsion stores its files under. They are on users' disks: never rename one.
enum StoredFileName {
    static let appFolder = "Emulsion"
    static let libraryIndex = "library.json"
    static let unreadableLibraryIndexPrefix = "library-unreadable-"
    static let importStagingPrefix = ".import-"
    static let recipes = "recipes.json"
    static let thumbnailsFolder = "Thumbnails"
    static let thumbnailExtension = "jpg"

    static var appFolderURL: URL { URL.applicationSupportDirectory.appending(path: appFolder, directoryHint: .isDirectory) }
    /// In Caches: the system may delete it when space is short, and the app renders again.
    static var thumbnailsFolderURL: URL {
        URL.cachesDirectory.appending(path: appFolder, directoryHint: .isDirectory).appending(
            path: thumbnailsFolder, directoryHint: .isDirectory)
    }
}
