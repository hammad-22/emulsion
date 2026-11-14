import Foundation

/// The process a photo is rendered through: the film negative → print chain, or the digicam
/// process (a mid-2000s compact CCD camera's in-camera JPEG, `Renderer+Digicam.swift`). The
/// controls of `Adjustments` mean different things in each (see `Adjustments`).
public enum RenderProcess: String, Codable, Sendable, CaseIterable {
    case film, digicam
}
