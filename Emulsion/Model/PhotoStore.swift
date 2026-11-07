import EmulsionCore
import SwiftUI

/// One photo: the original file (RAW or HEIC/JPEG) plus its edits.
struct PhotoRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let created: Date
    let fileName: String
    let isRAW: Bool
    var adjustments: Adjustments
}

/// Originals live in Application Support; edits are non-destructive and stored in an index.
@MainActor @Observable
final class PhotoStore {
    private(set) var photos: [PhotoRecord] = []
    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("library.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Emulsion", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
            let saved = try? JSONDecoder().decode([PhotoRecord].self, from: data)
        {
            photos = saved.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
        }
    }

    func url(for photo: PhotoRecord) -> URL { folder.appendingPathComponent(photo.fileName) }
    func photo(_ id: UUID) -> PhotoRecord? { photos.first { $0.id == id } }

    @discardableResult
    func add(_ data: Data, fileExtension: String) throws -> PhotoRecord {
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

    func update(_ id: UUID, adjustments: Adjustments) {
        guard let i = photos.firstIndex(where: { $0.id == id }), photos[i].adjustments != adjustments else { return }
        photos[i].adjustments = adjustments
        save()
    }

    func delete(_ id: UUID) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let file = url(for: photos[i])
        try? FileManager.default.removeItem(at: file)
        Task { await RenderService.shared.forget(file) }
        photos.remove(at: i)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(photos) { try? data.write(to: indexURL, options: .atomic) }
    }
}
