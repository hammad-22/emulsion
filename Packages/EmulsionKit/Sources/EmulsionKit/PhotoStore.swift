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
    /// False only if an unreadable index couldn't be moved aside: it must never be overwritten.
    private var canWriteIndex = true

    public convenience init() {
        self.init(folder: URL.applicationSupportDirectory.appending(path: "Emulsion", directoryHint: .isDirectory), renderService: .shared)
    }

    init(folder: URL, renderService: RenderService) {
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            photos = try savedIndex()
        } catch {
            recoverFromUnreadableIndex()
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
        let samples = Bundle.module.urls(forResourcesWithExtension: "jpg", subdirectory: "Samples") ?? []
        try insert(samples.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { (try Data(contentsOf: $0), $0.pathExtension) })
    }

    public func update(_ id: UUID, adjustments: Adjustments) {
        guard let i = photos.firstIndex(where: { $0.id == id }), photos[i].adjustments != adjustments else { return }
        do { try commit { $0[i].adjustments = adjustments } } catch { lastError = error }
    }

    public func delete(_ id: UUID) async {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let file = url(for: photos[i])
        do { try commit { $0.remove(at: i) } } catch {
            lastError = error
            return
        }
        try? FileManager.default.removeItem(at: file)
        await renderService.forget(file)
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
        photos = updated
    }

    /// The saved library, minus photos whose original is gone; empty on first launch.
    private func savedIndex() throws -> [PhotoRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return [] }
        return try JSONDecoder().decode([PhotoRecord].self, from: Data(contentsOf: indexURL)).filter {
            FileManager.default.fileExists(atPath: url(for: $0).path(percentEncoded: false))
        }
    }

    /// Keeps the unreadable index under a new name, so its edits can still be recovered,
    /// and lists the originals again with the default look.
    private func recoverFromUnreadableIndex() {
        lastError = .libraryUnreadable
        let kept = folder.appending(path: "library-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: indexURL, to: kept)
        } catch {
            canWriteIndex = false
        }
        let originals = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let recovered = originals.compactMap { file -> PhotoRecord? in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
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
