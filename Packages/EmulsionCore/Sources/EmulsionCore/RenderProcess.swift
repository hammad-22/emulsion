import Foundation

/// The process a photo is rendered through: the film negative → print chain, or the digicam
/// process (a mid-2000s compact CCD camera's in-camera JPEG, `Renderer+Digicam.swift`). The
/// controls of `Adjustments` mean different things in each (see `Adjustments`).
public enum RenderProcess: String, Codable, Sendable, CaseIterable {
    case film, digicam

    /// The engine model a recipe file names for this process. Film keeps the name it had before
    /// there were processes, so film recipes are byte-for-byte unchanged; an app that predates a
    /// process refuses its recipes (`recipeModelUnsupported`) instead of printing them as film.
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
