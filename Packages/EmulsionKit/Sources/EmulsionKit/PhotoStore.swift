import EmulsionCore
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Originals live in one folder (Application Support by default); edits are
/// non-destructive and stored in an index next to them. The index is written before the
/// library changes, so what the app shows is what the next launch finds.
@MainActor @Observable
public final class PhotoStore {
    public private(set) var photos: [PhotoRecord] = []
    /// The last library problem that no caller could be told about directly (loading,
    /// saving an edit, deleting), for the app to show. Set it to nil once shown.
    public var lastError: EmulsionError?
    let folder: URL
    let renderService: RenderService
    var indexURL: URL { folder.appending(path: "library.json") }
    /// False while the index on disk couldn't be read or moved aside: it must never be overwritten.
    private var canWriteIndex = true
    /// Set once a failed save is reported and cleared when one succeeds, so a full disk is
    /// reported once rather than on every slider rest.
    private var hasReportedSaveFailure = false

    public convenience init() {
        self.init(folder: URL.applicationSupportDirectory.appending(path: "Emulsion", directoryHint: .isDirectory), renderService: .shared)
    }

    init(folder: URL, renderService: RenderService) {
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved: Data
        do {
            saved = try Data(contentsOf: indexURL)
        } catch CocoaError.fileReadNoSuchFile {
            let originals = originalFiles()
            if !originals.isEmpty { recoverOriginals(originals) }
            return
        } catch {
            // Unreadable right now (e.g. file protection), not corrupt: keep it as it is.
            canWriteIndex = false
            recoverOriginals(originalFiles())
            return
        }
        do {
            photos = existingPhotos(try JSONDecoder().decode([PhotoRecord].self, from: saved))
        } catch {
            keepCorruptIndex()
            let readable = (try? JSONDecoder().decode([RecoverablePhotoRecord].self, from: saved))?.compactMap(\.photo) ?? []
            recoverOriginals(originalFiles(), preserving: existingPhotos(readable))
        }
    }

    public func url(for photo: PhotoRecord) -> URL { folder.appending(path: photo.fileName) }
    public func photo(_ id: UUID) -> PhotoRecord? { photos.first { $0.id == id } }

    /// Adds an original as delivered (e.g. by the photo picker), named after the type its
    /// bytes actually are, not what the sender said it might be.
    @discardableResult
    public func add(_ data: Data) throws -> PhotoRecord {
        let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
        return try add(data, fileExtension: type?.preferredFilenameExtension ?? "jpg")
    }

    @discardableResult
    public func add(_ data: Data, fileExtension: String) throws -> PhotoRecord {
        try insert([(data, fileExtension)])[0]
    }

    /// Adds the bundled synthetic sample photos (made by `Tools/make-sample-photos.swift`),
    /// so there is something to develop before the user imports their own.
    public func addSamples() throws {
        try insert(Self.sampleURLs.map { (try Data(contentsOf: $0), $0.pathExtension) })
    }

    /// The bundled sample photos, in the order they're added.
    public nonisolated static let sampleURLs: [URL] = (Bundle.module.urls(forResourcesWithExtension: "jpg", subdirectory: "Samples") ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    /// Deletes several photos, e.g. the library's selection.
    public func delete(_ ids: some Sequence<UUID>) async {
        let selected = Set(ids)
        let files = photos.filter { selected.contains($0.id) }.map { url(for: $0) }
        guard !files.isEmpty else { return }
        do { try commit { $0.removeAll { selected.contains($0.id) } } } catch {
            report(error)
            return
        }
        for file in files {
            do {
                try FileManager.default.removeItem(at: file)
            } catch CocoaError.fileNoSuchFile {
                // Already gone: nothing to report.
            } catch {
                report(.libraryDeleteFailed)
            }
            await renderService.forget(file)
        }
    }

    public func update(_ id: UUID, adjustments: Adjustments) {
        guard let i = photos.firstIndex(where: { $0.id == id }), photos[i].adjustments != adjustments else { return }
        do { try commit { $0[i].adjustments = adjustments } } catch { report(error) }
    }

    public func delete(_ id: UUID) async {
        await delete([id])
    }

    /// Copies originals in and lists them first, in the given order, with one index write.
    /// If anything fails, the files already copied are removed and the library is unchanged.
    @discardableResult
    private func insert(_ originals: [(data: Data, fileExtension: String)]) throws -> [PhotoRecord] {
        var added: [PhotoRecord] = []
        do {
            for original in originals {
                let id = UUID()
                let name = "\(id.uuidString).\(original.fileExtension.lowercased())"
                try original.data.write(to: folder.appending(path: name), options: .atomic)
                added.append(
                    PhotoRecord(
                        id: id, created: .now, fileName: name, isRAW: Developer.isRAW(original.data), adjustments: .defaults(for: id)))
            }
            try commit { $0.insert(contentsOf: added, at: 0) }
            return added
        } catch {
            for record in added { try? FileManager.default.removeItem(at: url(for: record)) }
            throw error
        }
    }

    /// Applies `change` to a copy of the library, writes it as the index, then shows it.
    private func commit(_ change: (inout [PhotoRecord]) -> Void) throws(EmulsionError) {
        guard canWriteIndex else { throw .librarySaveFailed }
        var updated = photos
        change(&updated)
        do {
            try JSONEncoder().encode(updated).write(to: indexURL, options: .atomic)
        } catch {
            throw .librarySaveFailed
        }
        hasReportedSaveFailure = false
        photos = updated
    }

    private func report(_ error: EmulsionError) {
        if error == .librarySaveFailed {
            guard !hasReportedSaveFailure else { return }
            hasReportedSaveFailure = true
        }
        lastError = error
    }

    /// Keeps a corrupt index under a new name, so its edits can still be recovered.
    private func keepCorruptIndex() {
        let kept = folder.appending(path: "library-unreadable-\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: indexURL, to: kept)
        } catch {
            canWriteIndex = false
        }
    }

    private func existingPhotos(_ records: [PhotoRecord]) -> [PhotoRecord] {
        records.filter { FileManager.default.fileExists(atPath: url(for: $0).path(percentEncoded: false)) }
    }

    private func originalFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
    }

    /// Lists originals again when the index can't be used, preserving edits from any
    /// independently readable records before applying defaults to the rest.
    private func recoverOriginals(_ originals: [URL], preserving readable: [PhotoRecord] = []) {
        lastError = .libraryUnreadable
        let saved = Dictionary(readable.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        let recovered = originals.compactMap { file -> PhotoRecord? in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
            if let record = saved[file.lastPathComponent] { return record }
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let isRAW = (try? Data(contentsOf: file, options: .mappedIfSafe)).map(Developer.isRAW) ?? false
            return PhotoRecord(id: id, created: created, fileName: file.lastPathComponent, isRAW: isRAW, adjustments: .defaults(for: id))
        }
        let newestFirst = recovered.sorted { $0.created > $1.created }
        // Written now, so the next launch finds the recovered list rather than no index;
        // shown either way.
        do { try commit { $0 = newestFirst } } catch { photos = newestFirst }
    }
}

private struct RecoverablePhotoRecord: Decodable {
    let photo: PhotoRecord?

    init(from decoder: any Decoder) {
        photo = try? PhotoRecord(from: decoder)
    }
}

extension Adjustments {
    /// The starting edit for a photo: the default look, with a grain seed derived from the
    /// photo's ID so re-renders, exports and resets match, and photos differ. Whole numbers
    /// 0…1023 keep float precision exact in the grain kernel.
    static func defaults(for id: UUID) -> Adjustments {
        var adjustments = Adjustments()
        adjustments.seed = Double(id.uuid.0) * 4 + Double(id.uuid.1 % 4)
        return adjustments
    }
}
