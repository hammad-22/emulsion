import EmulsionCore
import Foundation

public struct PhotoRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let created: Date
    public let fileName: String
    public let isRAW: Bool
    public var adjustments: Adjustments
    /// RAW only, saved after the first develop.
    var exposureAnchor: StoredExposureAnchor?

    public var isEdited: Bool { adjustments != .defaults(for: id) }
}

extension PhotoRecord {
    /// Only the ID and file name are required (MOV-128).
    public init(from decoder: any Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        id = try saved.decode(UUID.self, forKey: .id)
        fileName = try saved.decode(String.self, forKey: .fileName)
        created = try saved.decodeIfPresent(Date.self, forKey: .created) ?? .distantPast
        isRAW = try saved.decodeIfPresent(Bool.self, forKey: .isRAW) ?? false
        adjustments = try saved.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? .defaults(for: id)
        // A cache: one that doesn't decode is measured again.
        exposureAnchor = try? saved.decodeIfPresent(StoredExposureAnchor.self, forKey: .exposureAnchor)
    }
}
