import Foundation

/// A RAW photo's exposure anchor (MOV-134, MOV-141). See Packages/EmulsionKit/NOTES.md, "PhotoRecord and StoredExposureAnchor".
struct StoredExposureAnchor: Codable, Equatable, Sendable {
    let stops: Double
    /// The file it was measured from; its coding keys are part of the library index.
    let source: FileIdentity
}
