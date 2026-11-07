import EmulsionCore
import Foundation
import Observation

/// Originals live in one folder (Application Support by default); edits are
/// non-destructive and stored in an index next to them.
@MainActor @Observable
public final class PhotoStore {
    public private(set) var photos: [PhotoRecord] = []
    public let folder: URL
    private let renderService: RenderService
    private var indexURL: URL { folder.appendingPathComponent("library.json") }

    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Emulsion", isDirectory: true)
    }

    public init(folder: URL = PhotoStore.defaultFolder, renderService: RenderService = .shared) {
        self.folder = folder
        self.renderService = renderService
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
            let saved = try? JSONDecoder().decode([PhotoRecord].self, from: data)
        {
            photos = saved.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
        }
    }

    public func url(for photo: PhotoRecord) -> URL { folder.appendingPathComponent(photo.fileName) }
    public func photo(_ id: UUID) -> PhotoRecord? { photos.first { $0.id == id } }

    @discardableResult
    public func add(_ data: Data, fileExtension: String) throws -> PhotoRecord {
        let id = UUID()
        let name = "\(id.uuidString).\(fileExtension.lowercased())"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        var adjustments = Adjustments()
        // Grain seed derived from the photo's ID: stable for re-renders and exports,
        // different between photos. Whole numbers 0…1023 keep float precision exact.
        adjustments.seed = Double(id.uuid.0) * 4 + Double(id.uuid.1 % 4)
        let record = PhotoRecord(id: id, created: .now, fileName: name, isRAW: Developer.isRAW(data), adjustments: adjustments)
        photos.insert(record, at: 0)
        save()
        return record
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

    private func save() {
        if let data = try? JSONEncoder().encode(photos) { try? data.write(to: indexURL, options: .atomic) }
    }
}
