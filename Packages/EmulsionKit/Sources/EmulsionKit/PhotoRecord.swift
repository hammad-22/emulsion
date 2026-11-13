import EmulsionCore
import Foundation

/// One photo: the original file (RAW or HEIC/JPEG) plus its edits.
public struct PhotoRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let created: Date
    public let fileName: String
    public let isRAW: Bool
    public var adjustments: Adjustments
    /// RAW only, saved after the first develop; nil until then and for other photos.
    var exposureAnchor: StoredExposureAnchor?

    /// True once the edit differs from the default look the photo was imported with.
    public var isEdited: Bool { adjustments != .defaults(for: id) }
}

extension PhotoRecord {
    /// Only the ID and file name are required: any other field missing from the index gets
    /// a default, so adding a field never makes an existing library unreadable (MOV-128).
    public init(from decoder: any Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        id = try saved.decode(UUID.self, forKey: .id)
        fileName = try saved.decode(String.self, forKey: .fileName)
        created = try saved.decodeIfPresent(Date.self, forKey: .created) ?? .distantPast
        isRAW = try saved.decodeIfPresent(Bool.self, forKey: .isRAW) ?? false
        adjustments = try saved.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? .defaults(for: id)
        // A cache: one that doesn't decode is measured again rather than failing the record.
        exposureAnchor = try? saved.decodeIfPresent(StoredExposureAnchor.self, forKey: .exposureAnchor)
    }
}
