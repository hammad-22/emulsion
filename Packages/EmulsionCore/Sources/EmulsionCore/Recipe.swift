import Foundation

/// An artistic adjustment snapshot for the single built-in film model. A photo owns its grain
/// seed and its RAW white balance, which describes the light it was shot under.
public struct Recipe: Codable, Equatable, Identifiable, Sendable {
    public static let formatVersion = 1
    public static let engineModel = "emulsion-default-v1"
    public static let maximumFileSize = 65_536

    // Bounds combining-character sequences as well as visible character counts.
    private static let maximumNameLength = 80
    private static let maximumSummaryLength = 240
    private static let maximumMetadataSize = 4_096

    public let id: UUID
    public let name: String
    public let summary: String
    public let adjustments: Adjustments

    public init(id: UUID = UUID(), name: String, summary: String = "", adjustments: Adjustments) throws(EmulsionError) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = adjustments
        settings.seed = 0
        settings.whiteBalance = nil
        guard !name.isEmpty, name.count <= Self.maximumNameLength, summary.count <= Self.maximumSummaryLength,
            name.utf8.count + summary.utf8.count <= Self.maximumMetadataSize,
            !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            !summary.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            Field.allCases.allSatisfy({ settings[keyPath: $0.path].isFinite }), settings.clamped() == settings
        else { throw .invalidRecipe }
        self.id = id
        self.name = name
        self.summary = summary
        self.adjustments = settings
    }

    public func applying(to current: Adjustments) -> Adjustments {
        var result = adjustments
        result.seed = current.seed
        result.whiteBalance = current.whiteBalance
        return result
    }

    public func matches(_ current: Adjustments) -> Bool {
        applying(to: current) == current
    }

    public static func decode(_ data: Data) throws(EmulsionError) -> Recipe {
        guard data.count <= maximumFileSize else { throw .invalidRecipe }
        do { return try JSONDecoder().decode(Self.self, from: data) } catch let error as EmulsionError { throw error } catch {
            throw .invalidRecipe
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, engineModel, id, name, summary, adjustments }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .formatVersion) == Self.formatVersion else {
            throw EmulsionError.recipeVersionUnsupported
        }
        guard try container.decode(String.self, forKey: .engineModel) == Self.engineModel else {
            throw EmulsionError.recipeModelUnsupported
        }
        let settings = try container.nestedContainer(keyedBy: Field.self, forKey: .adjustments)
        var adjustments = Adjustments()
        for key in Field.allCases { adjustments[keyPath: key.path] = try settings.decode(Double.self, forKey: key) }
        try self.init(
            id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name),
            summary: container.decode(String.self, forKey: .summary), adjustments: adjustments)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(Self.engineModel, forKey: .engineModel)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(summary, forKey: .summary)
        var settings = container.nestedContainer(keyedBy: Field.self, forKey: .adjustments)
        for key in Field.allCases { try settings.encode(adjustments[keyPath: key.path], forKey: key) }
    }

    private enum Field: String, CodingKey, CaseIterable {
        case exposure, warmth, tint, color, highlights, shadows, grain, halation
        var path: WritableKeyPath<Adjustments, Double> {
            switch self {
            case .exposure: \.exposure
            case .warmth: \.warmth
            case .tint: \.tint
            case .color: \.color
            case .highlights: \.highlights
            case .shadows: \.shadows
            case .grain: \.grain
            case .halation: \.halation
            }
        }
    }
}
