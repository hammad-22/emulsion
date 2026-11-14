import Foundation

/// What a render is for. The digicam process compresses only exports through its in-camera JPEG
/// (a preview's 8 × 8 blocks would be sub-pixel); the film process renders both alike.
public enum RenderIntent: Sendable {
    case preview, export
}
