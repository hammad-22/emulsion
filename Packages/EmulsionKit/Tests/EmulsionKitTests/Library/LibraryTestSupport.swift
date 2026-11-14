import Foundation

@testable import EmulsionKit

/// POSIX modes the library tests put files and folders in.
enum FilePermissions {
    static let none = 0
    static let readOnlyFolder = 0o555
    static let folder = 0o755
    static let file = 0o644

    static func set(_ mode: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
}

extension TestLibrary {
    /// Replaces the photo's original with a locked folder, so deleting it fails. Unlock it with
    /// `FilePermissions.set(FilePermissions.folder, at:)` on the returned URL.
    func blockRemoval(of photo: PhotoRecord) throws -> URL {
        let original = store.url(for: photo)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try TestPhoto.jpeg.write(to: original.appending(path: "blocked.jpg"))
        try FilePermissions.set(FilePermissions.none, at: original)
        return original
    }

    /// A folder where the index should be makes every index write fail.
    func blockIndexWrites() throws {
        try FileManager.default.removeItem(at: store.indexURL)
        try FileManager.default.createDirectory(at: store.indexURL, withIntermediateDirectories: false)
    }

    func addPhotos(_ count: Int) async throws -> [PhotoRecord] {
        var photos: [PhotoRecord] = []
        for _ in 0..<count { photos.append(try await store.add(TestPhoto.jpeg, fileExtension: "jpg")) }
        return photos
    }

    var unreadableIndexBackups: [URL] {
        get throws {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(StoredFileName.unreadableLibraryIndexPrefix) }
        }
    }
}
