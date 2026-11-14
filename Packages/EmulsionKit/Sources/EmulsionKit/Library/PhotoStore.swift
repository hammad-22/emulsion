import EmulsionCore
import Foundation
import Observation

/// Originals and an index of their non-destructive edits, in one folder. The index is written
/// before the library changes, so what the app shows is what the next launch finds.
@MainActor @Observable
public final class PhotoStore {
    public private(set) var photos: [PhotoRecord] = []
    /// A problem no caller could be told about directly; set it to nil once shown.
    public var lastError: EmulsionError?
    let folder: URL
    private let importer: OriginalImporter
    let renderService: RenderService
    var indexURL: URL { folder.appending(path: StoredFileName.libraryIndex) }
    /// False while the index on disk couldn't be read or moved aside: it must never be overwritten.
    private var canWriteIndex = true
    /// So a full disk is reported once rather than on every slider rest.
    private var hasReportedSaveFailure = false
    private var unsavedExposureAnchors: [UUID: StoredExposureAnchor] = [:]
    private var exposureAnchorSave: Task<Void, Never>?
    static let exposureAnchorSaveDelay = Duration.seconds(1)

    public convenience init() {
        self.init(folder: StoredFileName.appFolderURL, renderService: .shared)
    }

    init(folder: URL, renderService: RenderService, importer: OriginalImporter = OriginalImporter()) {
        self.importer = importer
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        loadIndex()
        restoreExposureAnchors()
        Task { [weak self, anchors = renderService.measuredExposureAnchors] in
            for await (file, anchor) in anchors { self?.keepExposureAnchor(anchor, for: file) }
        }
    }

    private func loadIndex() {
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

    /// Cancellation before the commit removes only this import's files; a committed import succeeds.
    @discardableResult
    public func add(_ data: Data) async throws -> PhotoRecord {
        try await insert([.data(data, fileExtension: nil)])[0]
    }

    /// `look` becomes the starting edit, with this photo's own grain seed.
    @discardableResult
    public func add(_ data: Data, fileExtension: String, look: Adjustments = Adjustments()) async throws -> PhotoRecord {
        try await insert([.data(data, fileExtension: fileExtension)], look: look)[0]
    }

    public func addSamples() async throws {
        try await insert(Self.sampleURLs.map { .file($0) })
    }

    public nonisolated static let sampleURLs: [URL] =
        (Bundle.module.urls(forResourcesWithExtension: sampleFileExtension, subdirectory: samplesFolder) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    private nonisolated static let samplesFolder = "Samples"
    private nonisolated static let sampleFileExtension = "jpg"

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

    @discardableResult
    private func insert(_ originals: [OriginalImporter.Original], look: Adjustments = Adjustments()) async throws -> [PhotoRecord] {
        guard canWriteIndex else { throw EmulsionError.librarySaveFailed }
        var added = try await importer.prepare(originals, in: folder)
        for index in added.indices { added[index].adjustments = .defaults(for: added[index].id, look: look) }
        do {
            try Task.checkCancellation()
            // No suspension between reading the current photos, committing, and publishing:
            // imports cannot restore a deleted record or overwrite an intervening edit.
            try commit { $0.insert(contentsOf: added, at: 0) }
            return added
        } catch {
            await importer.remove(added, from: folder)
            throw error
        }
    }

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

    /// The render service measures again for an original that changed.
    private func restoreExposureAnchors() {
        for photo in photos {
            if let anchor = photo.exposureAnchor { renderService.restoreExposureAnchor(anchor, for: url(for: photo)) }
        }
    }

    /// Saves at once, then batches anchors measured within `exposureAnchorSaveDelay`, so opening a
    /// library of unmeasured RAWs writes the index about once a second, not once per photo.
    private func keepExposureAnchor(_ anchor: StoredExposureAnchor, for file: URL) {
        guard let photo = photos.first(where: { $0.fileName == file.lastPathComponent }) else { return }
        unsavedExposureAnchors[photo.id] = anchor
        guard exposureAnchorSave == nil else { return }
        saveExposureAnchors()
        exposureAnchorSave = Task {
            try? await Task.sleep(for: Self.exposureAnchorSaveDelay)
            exposureAnchorSave = nil
            if !unsavedExposureAnchors.isEmpty { saveExposureAnchors() }
        }
    }

    private func saveExposureAnchors() {
        let anchors = unsavedExposureAnchors
        unsavedExposureAnchors = [:]
        do {
            try commit { photos in
                for i in photos.indices {
                    if let anchor = anchors[photos[i].id] { photos[i].exposureAnchor = anchor }
                }
            }
        } catch {
            report(error)
        }
    }

    private func report(_ error: EmulsionError) {
        if error == .librarySaveFailed {
            guard !hasReportedSaveFailure else { return }
            hasReportedSaveFailure = true
        }
        lastError = error
    }

    /// So its edits can still be recovered.
    private func keepCorruptIndex() {
        let name = "\(StoredFileName.unreadableLibraryIndexPrefix)\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).json"
        let kept = folder.appending(path: name)
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

    /// Keeps the edits of any readable records; the rest get the default look.
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
        // Written now, so the next launch finds the recovered list rather than no index.
        do { try commit { $0 = newestFirst } } catch { photos = newestFirst }
    }
}

/// A record that may be damaged, so one bad record doesn't discard the others' edits.
private struct RecoverablePhotoRecord: Decodable {
    let photo: PhotoRecord?

    init(from decoder: any Decoder) {
        photo = try? PhotoRecord(from: decoder)
    }
}
