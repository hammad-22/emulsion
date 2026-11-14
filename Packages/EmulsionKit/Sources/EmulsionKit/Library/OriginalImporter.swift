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
        let staging = folder.appending(path: "\(StoredFileName.importStagingPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
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
                let fileExtension = try Self.fileExtension(of: data, supplied: suppliedExtension)
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

    /// The supplied extension, or the one the image's type prefers; plain ASCII letters and digits only.
    private static func fileExtension(of data: Data, supplied: String?) throws(EmulsionError) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let identifier = CGImageSourceGetType(source),
            let type = UTType(identifier as String)
        else { throw .unsupportedPhoto }
        let fileExtension = supplied ?? type.preferredFilenameExtension ?? fallbackFileExtension
        guard !fileExtension.isEmpty, fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw .unsupportedPhoto
        }
        return fileExtension
    }

    private static let fallbackFileExtension = "jpg"
}
