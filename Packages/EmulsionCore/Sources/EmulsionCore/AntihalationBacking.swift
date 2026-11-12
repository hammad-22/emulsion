/// What stops light at the back of the negative from returning to the emulsion (halation).
/// The magnitudes are estimates: no film maker publishes a halation measurement for either backing
/// (`docs/FILM-THEORY.md` §6.1).
public enum AntihalationBacking: String, Codable, CaseIterable, Sendable {
    /// No backing (e.g. rem-jet removed): the full single-bounce return, the strongest red glow.
    case none
    /// An absorbing anti-halation undercoat between the emulsion and the base, as on current
    /// motion-picture negatives.
    case undercoat
    /// A removable black backing on the back of the base.
    case remJet

    /// Share of the unbacked return that comes back to the emulsion. Both backings are estimated at
    /// 0.05 and deliberately equal: Kodak says only that the undercoat "performs equally" to rem-jet
    /// (VISION3 AHU talking points, May 2025).
    var returnFraction: Double {
        switch self {
        case .none: 1
        case .undercoat, .remJet: 0.05
        }
    }
}
