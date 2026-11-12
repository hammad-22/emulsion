import Foundation

/// Descriptive artistic choices using the current model, not measured matches to named film stocks.
public enum CuratedLooks {
    // Amounts are artistic defaults chosen to express each description, not fitted stock data.
    public static let recipes: [Recipe] = [
        make(
            "00000000-0000-0000-0000-000000000001", String(localized: "Everyday", bundle: .module),
            String(localized: "Balanced color with gentle texture.", bundle: .module)
        ) { _ in },
        make(
            "00000000-0000-0000-0000-000000000002", String(localized: "Warm Light", bundle: .module),
            String(localized: "Warm printer lights and soft, open shadows.", bundle: .module)
        ) {
            $0.warmth = 0.25
            $0.shadows = 0.2
            $0.highlights = 0.15
            $0.grain = 0.25
        },
        make(
            "00000000-0000-0000-0000-000000000003", String(localized: "Quiet Color", bundle: .module),
            String(localized: "Restrained color, cool light and fine texture.", bundle: .module)
        ) {
            $0.color = -0.3
            $0.warmth = -0.12
            $0.grain = 0.15
            $0.halation = 0.15
        },
        make(
            "00000000-0000-0000-0000-000000000004", String(localized: "Night Glow", bundle: .module),
            String(localized: "Rich color, lifted shadows and a stronger glow.", bundle: .module)
        ) {
            $0.color = 0.15
            $0.shadows = 0.3
            $0.highlights = 0.25
            $0.halation = 0.65
            $0.grain = 0.45
        },
    ].compactMap { $0 }

    private static func make(_ id: String, _ name: String, _ summary: String, edit: (inout Adjustments) -> Void) -> Recipe? {
        var adjustments = Adjustments()
        edit(&adjustments)
        guard let id = UUID(uuidString: id) else { return nil }
        return try? Recipe(id: id, name: name, summary: summary, adjustments: adjustments)
    }
}
