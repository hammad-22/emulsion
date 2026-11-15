import Foundation

/// The process a photo is rendered through: film negative → print, or the digicam process.
public enum RenderProcess: String, Codable, Sendable, CaseIterable {
    case film, digicam

    /// The engine model a recipe names; film keeps its pre-process name so old recipes are unchanged.
    public var engineModel: String {
        switch self {
        case .film: "emulsion-default-v1"
        case .digicam: "emulsion-digicam-v1"
        }
    }

    /// The process a recipe's engine model names; nil for one this version doesn't know.
    public init?(engineModel: String) {
        guard let process = Self.allCases.first(where: { $0.engineModel == engineModel }) else { return nil }
        self = process
    }
}
