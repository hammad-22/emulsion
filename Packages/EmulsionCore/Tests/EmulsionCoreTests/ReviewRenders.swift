import Foundation
import Testing

@testable import EmulsionCore

/// Full-resolution renders of local CC0 samples for look reviews (MOV-146): each sample (name ending
/// in `_CC0.dng`, any case) under `EMULSION_REVIEW_SAMPLES` is developed at full size and written as a
/// Display P3 JPEG, `<sample>.<look>.<label>.jpg`, into `EMULSION_REVIEW_DIR`. `Tools/review-renders.sh`
/// runs this on two commits so the pairs sit side by side; never review a look on the frozen
/// test scenes, which are 240 px. Opt-in, so CI and plain `swift test` skip it.
///
/// Kept free of other test-target helpers: the script copies this file into an older checkout
/// when that checkout does not have it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_REVIEW_DIR"] != nil), .serialized)
struct ReviewRenders {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var outputDirectory: URL? { environment["EMULSION_REVIEW_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
    /// `before` or `after` (any label; the script passes those two).
    static var label: String { environment["EMULSION_REVIEW_LABEL"] ?? "render" }
    static var samplesDirectory: URL {
        environment["EMULSION_REVIEW_SAMPLES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.homeDirectory.appending(path: "Documents/Emulsion Research/samples/proraw-misc")
    }

    /// The default look with a fixed grain seed, so a pair differs only by the engine.
    static let defaultLook: Adjustments = {
        var a = Adjustments()
        a.seed = 7
        return a
    }()
    /// The film process alone, and the default look.
    static let looks: [(name: String, adjustments: Adjustments)] = [("neutral", .neutral), ("default", defaultLook)]

    /// Only CC0 samples: their licence lets the renders be shared in a PR.
    static func samples() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: samplesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.lowercased().hasSuffix("_cc0.dng") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test func writesFullResolutionRenders() throws {
        let output = try #require(Self.outputDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples = try Self.samples()
        try #require(!samples.isEmpty, "no *_CC0.dng samples in \(Self.samplesDirectory.path)")
        let renderer = try Renderer()
        for url in samples {
            let name = url.deletingPathExtension().lastPathComponent
            let negative = try renderer.developer.develop(Data(contentsOf: url))
            for look in Self.looks {
                let rendered = try renderer.render(negative, look.adjustments)
                let file = output.appending(path: "\(name).\(look.name).\(Self.label).jpg")
                try renderer.export(rendered, format: .jpeg, quality: 0.95).write(to: file)
                print("\(file.lastPathComponent): \(Int(rendered.extent.width))×\(Int(rendered.extent.height))")
            }
        }
    }
}
