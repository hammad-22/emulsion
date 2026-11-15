import CoreGraphics
import CryptoKit
import EmulsionCore
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Rendered thumbnails kept on disk, so a relaunched library doesn't develop every visible photo
/// again. See Packages/EmulsionKit/NOTES.md, "ThumbnailFiles".
final class ThumbnailFiles: Sendable {
    /// About 2,800 grid thumbnails at 23 KB (bundled samples at 372 px on the Duo simulator, measured).
    static let byteLimit = 64 << 20
    /// Visually lossless at thumbnail size (artistic).
    private static let jpegQuality = 0.9
    /// Trimming stops at this share of the limit, so the next few writes don't trim again.
    private static let trimmedShare = 0.75

    /// This build's folder: a new build may render differently, so it never reads another's.
    let folder: URL
    private let byteLimit: Int
    /// Bytes stored in `folder`; nil until the first write prepares the folder and counts them.
    /// Writes run concurrently, so preparing happens under this lock, once.
    private let storedBytes = Mutex<Int?>(nil)
    /// True while a trim runs, so concurrent writes don't trim the same files twice.
    private let isTrimming = Mutex(false)

    init(parent: URL = StoredFileName.thumbnailsFolderURL, byteLimit: Int = ThumbnailFiles.byteLimit) {
        folder = parent.appending(path: Self.buildIdentity, directoryHint: .isDirectory)
        self.byteLimit = byteLimit
    }

    /// The stored thumbnail, decoded now so the caller never decodes it on the main actor.
    func image(_ key: ThumbnailCache.Key) -> CGImage? {
        guard let file = file(for: key), let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        // The modification date orders eviction: least recently shown first.
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))
        return image
    }

    func keep(_ image: CGImage, _ key: ThumbnailCache.Key) {
        guard let file = file(for: key), let data = Self.jpeg(image) else { return }
        guard prepareFolderOnce(), (try? data.write(to: file, options: .atomic)) != nil else { return }
        let total = storedBytes.withLock { bytes in
            let total = (bytes ?? 0) + data.count
            bytes = total
            return total
        }
        if total > byteLimit { trim() }
    }

    /// Removes every stored thumbnail of a photo (deleted, or its file changed).
    func remove(_ url: URL) {
        let prefix = Self.digest(Data(url.absoluteString.utf8), length: Self.photoDigestLength)
        for (file, size, _) in storedFiles() where file.lastPathComponent.hasPrefix(prefix) {
            if (try? FileManager.default.removeItem(at: file)) != nil { storedBytes.withLock { $0 = $0.map { $0 - size } } }
        }
    }

    /// `<photo>-<edit>.jpg`: the photo part lets `remove` find a photo's files; the edit part covers
    /// the file's size and date, the edit and the size, so any change misses instead of serving a stale image.
    private func file(for key: ThumbnailCache.Key) -> URL? {
        guard let source = FileIdentity(key.url), let edit = try? Self.encoder.encode(key.adjustments) else { return nil }
        let identity = "\(source.byteCount)|\(source.modified.timeIntervalSinceReferenceDate)|\(key.pixels)|"
        let photo = Self.digest(Data(key.url.absoluteString.utf8), length: Self.photoDigestLength)
        let name = photo + "-" + Self.digest(Data(identity.utf8) + edit)
        return folder.appending(path: name).appendingPathExtension(StoredFileName.thumbnailExtension)
    }

    /// Creates this build's folder, removes other builds' and counts what's already stored; false
    /// if the folder can't be made.
    private func prepareFolderOnce() -> Bool {
        storedBytes.withLock { bytes in
            guard bytes == nil else { return true }
            let parent = folder.deletingLastPathComponent()
            guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
            let builds = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            for build in builds where build.lastPathComponent != folder.lastPathComponent { try? FileManager.default.removeItem(at: build) }
            bytes = storedFiles().reduce(0) { $0 + $1.size }
            return true
        }
    }

    /// Deletes the least recently shown thumbnails until the folder is back under its limit,
    /// always keeping the newest.
    private func trim() {
        let started = isTrimming.withLock { trimming in
            guard !trimming else { return false }
            trimming = true
            return true
        }
        guard started else { return }
        defer { isTrimming.withLock { $0 = false } }
        let files = storedFiles().sorted { $0.modified < $1.modified }
        var total = files.reduce(0) { $0 + $1.size }
        let target = Int(Double(byteLimit) * Self.trimmedShare)
        for (file, size, _) in files.dropLast() where total > target {
            if (try? FileManager.default.removeItem(at: file)) != nil { total -= size }
        }
        storedBytes.withLock { $0 = total }
    }

    func storedFiles() -> [(url: URL, size: Int, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Hex digits of the photo's digest in a file name; 64 bits, so photos never collide in practice.
    private static let photoDigestLength = 16

    private static func digest(_ data: Data, length: Int = SHA256.byteCount * 2) -> String {
        String(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(length))
    }

    /// The app's version and its executable's size and date: any rebuild changes it.
    private static let buildIdentity: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let executable = Bundle.main.executableURL.flatMap(FileIdentity.init)
        let identity = "\(version)|\(executable?.byteCount ?? 0)|\(executable?.modified.timeIntervalSinceReferenceDate ?? 0)"
        return digest(Data(identity.utf8), length: photoDigestLength)
    }()
}
