import EmulsionCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns only original preparation; library snapshots and index commits stay in PhotoStore.
actor OriginalImporter {
    enum Original: Sendable {
        case data(Data, fileExtension: String?)
        case file(URL)
    }

    private let didPrepare: @Sendable (isolated OriginalImporter) async throws -> Void

    init(didPrepare: @escaping @Sendable (isolated OriginalImporter) async throws -> Void = { _ in }) {
        self.didPrepare = didPrepare
    }

    func prepare(_ originals: [Original], in folder: URL) async throws -> [PhotoRecord] {
        var added: [PhotoRecord] = []
        // Nested staging names are never mistaken for recoverable library originals.
        let staging = folder.appending(path: ".import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            for original in originals {
                try Task.checkCancellation()
                let data: Data
                let suppliedExtension: String?
                switch original {
                case .data(let bytes, let fileExtension):
                    data = bytes
                    suppliedExtension = fileExtension
                case .file(let url):
                    data = try Data(contentsOf: url)
                    suppliedExtension = url.pathExtension
                }
                let source = CGImageSourceCreateWithData(data as CFData, nil)
                guard let source, let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String) else {
                    throw EmulsionError.unsupportedPhoto
                }
                let fileExtension = suppliedExtension ?? type.preferredFilenameExtension ?? "jpg"
                guard !fileExtension.isEmpty, fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                    throw EmulsionError.unsupportedPhoto
                }
                let id = UUID()
                let name = "\(id.uuidString).\(fileExtension.lowercased())"
                let staged = staging.appending(path: name)
                try Task.checkCancellation()
                try data.write(to: staged, options: .atomic)
                try Task.checkCancellation()
                // moveItem fails if the destination already exists; never own or remove it.
                try FileManager.default.moveItem(at: staged, to: folder.appending(path: name))
                added.append(
                    PhotoRecord(id: id, created: .now, fileName: name, isRAW: Developer.isRAW(data), adjustments: .defaults(for: id)))
            }
            try await didPrepare(self)
            try Task.checkCancellation()
            return added
        } catch {
            remove(added, from: folder)
            if error is CancellationError { throw error }
            throw (error as? EmulsionError) ?? .librarySaveFailed
        }
    }

    func remove(_ records: [PhotoRecord], from folder: URL) {
        for record in records { try? FileManager.default.removeItem(at: folder.appending(path: record.fileName)) }
    }
}
