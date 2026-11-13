import EmulsionCore
import Foundation
import Observation

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
    private let importer: OriginalImporter
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

    init(folder: URL, renderService: RenderService, importer: OriginalImporter = OriginalImporter()) {
        self.importer = importer
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        loadIndex()
        restoreExposureAnchors()
        renderService.onExposureAnchorMeasured { [weak self] file, stops in
            Task { @MainActor in self?.keepExposureAnchor(stops, for: file) }
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

    /// Prepares the original off the main actor, then commits against the latest library.
    /// Cancellation before commit removes only this import's files. Once committed, an
    /// import succeeds even if its caller is cancelled immediately afterward.
    @discardableResult
    public func add(_ data: Data) async throws -> PhotoRecord {
        try await insert([.data(data, fileExtension: nil)])[0]
    }

    /// Adds an original with `look` as its starting edit (a camera recipe), given this photo's
    /// own grain seed. The file itself is stored untouched.
    @discardableResult
    public func add(_ data: Data, fileExtension: String, look: Adjustments = Adjustments()) async throws -> PhotoRecord {
        try await insert([.data(data, fileExtension: fileExtension)], look: look)[0]
    }

    /// Adds all bundled synthetic samples with one index commit.
    public func addSamples() async throws {
        try await insert(Self.sampleURLs.map { .file($0) })
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

    /// Gives the render service every saved anchor that still matches its original.
    private func restoreExposureAnchors() {
        for photo in photos {
            let file = url(for: photo)
            guard let anchor = photo.exposureAnchor, anchor.matches(file) else { continue }
            renderService.restoreExposureAnchor(anchor.stops, for: file)
        }
    }

    /// Saves a RAW photo's newly measured anchor with its record. It's a cache: if the save
    /// fails, the next launch measures it again, so the failure isn't reported.
    private func keepExposureAnchor(_ stops: Double, for file: URL) {
        guard let i = photos.firstIndex(where: { url(for: $0) == file }), photos[i].isRAW,
            let source = StoredExposureAnchor.Source(url(for: photos[i]))
        else { return }
        let anchor = StoredExposureAnchor(stops: stops, source: source)
        guard photos[i].exposureAnchor != anchor else { return }
        try? commit { $0[i].exposureAnchor = anchor }
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
    /// Grain seeds are whole numbers below this: small whole numbers keep float precision exact
    /// in the grain kernel.
    static let grainSeedCount = 1024

    /// The starting edit for a photo: `look` (the default look unless a recipe was chosen), with
    /// a grain seed (0 ..< `grainSeedCount`) derived from the photo's ID so re-renders, exports
    /// and resets match, and photos differ.
    static func defaults(for id: UUID, look: Adjustments = Adjustments()) -> Adjustments {
        var adjustments = look
        adjustments.seed = Double(id.uuid.0) * 4 + Double(id.uuid.1 % 4)
        return adjustments
    }
}
