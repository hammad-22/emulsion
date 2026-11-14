import EmulsionCore

/// The editor's controls, grouped the way the film process is: exposure and local tone,
/// printer lights and color density, then texture. Shared so iOS and Mac show the same
/// controls with the same ranges; the iPhone panel shows one group at a time. The digicam
/// process uses the same controls, two of them under its own names (`controls(for:)`).
public enum AdjustmentGroup: String, CaseIterable, Identifiable, Sendable {
    case light, color, texture

    public var id: Self { self }

    /// The ranges `Adjustments.clamped()` enforces before rendering; a test keeps them in step.
    static let exposureRange: ClosedRange<Double> = -3...3
    static let balanceRange: ClosedRange<Double> = -1...1
    static let amountRange: ClosedRange<Double> = 0...1

    public var title: String {
        switch self {
        case .light: String(localized: "Light", bundle: .module)
        case .color: String(localized: "Color", bundle: .module)
        case .texture: String(localized: "Texture", bundle: .module)
        }
    }

    /// The one control whose value differs between two edits, or nil when none or several
    /// do (Reset Edits): a ruler move changes exactly one.
    public static func changedControl(from old: Adjustments, to new: Adjustments) -> (
        group: AdjustmentGroup, control: AdjustmentControl.ID
    )? {
        let changed = allCases.flatMap { group in
            group.controls(for: .film).filter { old[keyPath: $0.keyPath] != new[keyPath: $0.keyPath] }.map {
                (group: group, control: $0.id)
            }
        }
        return changed.count == 1 ? changed[0] : nil
    }

    /// The group's controls, titled for `process`: in the digicam process Grain is sensor noise and
    /// Halation the in-camera processing (sharpening, fringing, JPEG).
    public func controls(for process: RenderProcess) -> [AdjustmentControl] {
        switch self {
        case .light:
            [
                .init(
                    id: "exposure", title: String(localized: "Exposure", bundle: .module), keyPath: \.exposure, range: Self.exposureRange,
                    unit: .stops),
                .init(
                    id: "highlights", title: String(localized: "Highlights", bundle: .module), keyPath: \.highlights,
                    range: Self.balanceRange),
                .init(id: "shadows", title: String(localized: "Shadows", bundle: .module), keyPath: \.shadows, range: Self.balanceRange),
            ]
        case .color:
            [
                .init(id: "warmth", title: String(localized: "Warmth", bundle: .module), keyPath: \.warmth, range: Self.balanceRange),
                .init(id: "tint", title: String(localized: "Tint", bundle: .module), keyPath: \.tint, range: Self.balanceRange),
                .init(id: "color", title: String(localized: "Color", bundle: .module), keyPath: \.color, range: Self.balanceRange),
            ]
        case .texture:
            switch process {
            case .film:
                [
                    .init(id: "grain", title: String(localized: "Grain", bundle: .module), keyPath: \.grain, range: Self.amountRange),
                    .init(
                        id: "halation", title: String(localized: "Halation", bundle: .module), keyPath: \.halation, range: Self.amountRange),
                ]
            case .digicam:
                [
                    .init(id: "grain", title: String(localized: "Noise", bundle: .module), keyPath: \.grain, range: Self.amountRange),
                    .init(
                        id: "halation", title: String(localized: "Processing", bundle: .module), keyPath: \.halation,
                        range: Self.amountRange),
                ]
            }
        }
    }
}

/// One adjustment: its editable value, range and display units.
public struct AdjustmentControl: Identifiable {
    enum Unit { case stops, amount }

    /// Stable across processes and languages, unlike the title.
    public let id: String
    public let title: String
    public let keyPath: WritableKeyPath<Adjustments, Double>
    public let range: ClosedRange<Double>
    let unit: Unit

    init(id: String, title: String, keyPath: WritableKeyPath<Adjustments, Double>, range: ClosedRange<Double>, unit: Unit = .amount) {
        self.id = id
        self.title = title
        self.keyPath = keyPath
        self.range = range
        self.unit = unit
    }

    /// A visible ruler tick and an accessible adjustment step.
    public var increment: Double { unit == .stops ? 0.1 : 0.01 }

    /// The value with a sign, e.g. "+0.7 EV" or "-35".
    public func formatted(_ value: Double) -> String {
        switch unit {
        case .stops:
            let stops = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            return String(localized: "\(stops) EV", bundle: .module, comment: "Exposure in stops, e.g. +0.7 EV")
        case .amount: return (value * 100).formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
        }
    }
}
