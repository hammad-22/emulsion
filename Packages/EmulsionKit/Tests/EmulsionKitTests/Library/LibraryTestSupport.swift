import Foundation

@testable import EmulsionKit

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
    /// Unlock the returned URL with `FilePermissions.folder` after the test.
    func blockRemoval(of photo: PhotoRecord) throws -> URL {
        let original = store.url(for: photo)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try TestPhoto.jpeg.write(to: original.appending(path: "blocked.jpg"))
        try FilePermissions.set(FilePermissions.none, at: original)
        return original
    }

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
