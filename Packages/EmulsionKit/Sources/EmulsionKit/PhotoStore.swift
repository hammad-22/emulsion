import EmulsionCore
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Originals live in one folder (Application Support by default); edits are
/// non-destructive and stored in an index next to them.
@MainActor @Observable
public final class PhotoStore {
    public private(set) var photos: [PhotoRecord] = []
    let folder: URL
    let renderService: RenderService
    private var indexURL: URL { folder.appending(path: "library.json") }

    public convenience init() {
        self.init(folder: URL.applicationSupportDirectory.appending(path: "Emulsion", directoryHint: .isDirectory), renderService: .shared)
    }

    init(folder: URL, renderService: RenderService) {
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
            let saved = try? JSONDecoder().decode([PhotoRecord].self, from: data)
        {
            photos = saved.filter {
                FileManager.default.fileExists(atPath: folder.appending(path: $0.fileName).path(percentEncoded: false))
            }
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
        let record = try insert(data, fileExtension: fileExtension)
        save()
        return record
    }

    /// Adds the bundled synthetic sample photos (made by `Tools/make-sample-photos.swift`),
    /// so there is something to develop before the user imports their own.
    public func addSamples() throws {
        let samples = Bundle.module.urls(forResourcesWithExtension: "jpg", subdirectory: "Samples") ?? []
        defer { save() }
        for url in samples.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            try insert(Data(contentsOf: url), fileExtension: url.pathExtension)
        }
    }

    public func update(_ id: UUID, adjustments: Adjustments) {
        guard let i = photos.firstIndex(where: { $0.id == id }), photos[i].adjustments != adjustments else { return }
        photos[i].adjustments = adjustments
        save()
    }

    public func delete(_ id: UUID) async {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let file = url(for: photos[i])
        try? FileManager.default.removeItem(at: file)
        photos.remove(at: i)
        save()
        await renderService.forget(file)
    }

    @discardableResult
    private func insert(_ data: Data, fileExtension: String) throws -> PhotoRecord {
        let id = UUID()
        let name = "\(id.uuidString).\(fileExtension.lowercased())"
        try data.write(to: folder.appending(path: name), options: .atomic)
        let record = PhotoRecord(id: id, created: .now, fileName: name, isRAW: Developer.isRAW(data), adjustments: .defaults(for: id))
        photos.insert(record, at: 0)
        return record
    }

    private func save() {
        if let data = try? JSONEncoder().encode(photos) { try? data.write(to: indexURL, options: .atomic) }
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
