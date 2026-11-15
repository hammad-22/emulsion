import Foundation

/// An artistic adjustment snapshot for one of the built-in render processes. A photo owns its grain
/// seed and its RAW white balance, which describes the light it was shot under.
public struct Recipe: Codable, Equatable, Identifiable, Sendable {
    /// The format written. Format 2 added the required `backing` (MOV-32), `grainSize` and `grainColor` (MOV-30).
    public static let formatVersion = 2
    /// Formats read: format 1 (no backing) prints with rem-jet.
    static let readableFormatVersions: ClosedRange<Int> = 1...formatVersion
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
            // Also rejects NaN and ±infinity: clamping changes them (NaN never equals itself).
            settings.clamped() == settings
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
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard Self.readableFormatVersions.contains(version) else { throw EmulsionError.recipeVersionUnsupported }
        guard let process = RenderProcess(engineModel: try container.decode(String.self, forKey: .engineModel)) else {
            throw EmulsionError.recipeModelUnsupported
        }
        let settings = try container.nestedContainer(keyedBy: Field.self, forKey: .adjustments)
        var adjustments = Adjustments()
        adjustments.process = process
        for field in Self.numericFields where version > 1 || !Self.formatTwoFields.contains(field.key) {
            adjustments[keyPath: field.path] = try settings.decode(Double.self, forKey: field.key)
        }
        // Format 1 has no backing or grain size and color (such keys there are unknown and ignored,
        // as format 1 readers ignore them): it prints with their defaults; format 2 requires them.
        adjustments.backing = version == 1 ? .remJet : try settings.decode(AntihalationBacking.self, forKey: .backing)
        try self.init(
            id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name),
            summary: container.decode(String.self, forKey: .summary), adjustments: adjustments)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(adjustments.process.engineModel, forKey: .engineModel)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(summary, forKey: .summary)
        var settings = container.nestedContainer(keyedBy: Field.self, forKey: .adjustments)
        for field in Self.numericFields { try settings.encode(adjustments[keyPath: field.path], forKey: field.key) }
        try settings.encode(adjustments.backing, forKey: .backing)
    }

    /// The keys of the `adjustments` object: the numeric adjustments and the backing.
    private enum Field: String, CodingKey {
        case exposure, warmth, tint, color, highlights, shadows, grain, halation, grainSize, grainColor, backing
    }

    private static let formatTwoFields: Set<Field> = [.grainSize, .grainColor]

    private static var numericFields: [(key: Field, path: WritableKeyPath<Adjustments, Double>)] {
        [
            (.exposure, \.exposure), (.warmth, \.warmth), (.tint, \.tint), (.color, \.color), (.highlights, \.highlights),
            (.shadows, \.shadows), (.grain, \.grain), (.halation, \.halation), (.grainSize, \.grainSize), (.grainColor, \.grainColor),
        ]
    }
}
