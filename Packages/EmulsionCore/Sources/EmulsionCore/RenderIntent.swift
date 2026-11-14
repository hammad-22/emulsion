import Foundation

/// What a render is for: only digicam exports go through the in-camera JPEG.
public enum RenderIntent: Sendable {
    case preview, export
}
