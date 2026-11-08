import EmulsionCore
import Foundation

/// One photo: the original file (RAW or HEIC/JPEG) plus its edits.
public struct PhotoRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let created: Date
    public let fileName: String
    public let isRAW: Bool
    public var adjustments: Adjustments
}
