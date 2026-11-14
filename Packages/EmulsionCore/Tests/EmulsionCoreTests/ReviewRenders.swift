import Foundation
import Testing

@testable import EmulsionCore

/// Full-resolution renders of local CC0 samples for look reviews (MOV-146): each sample (name ending
/// in `_CC0.dng`, any case) under `EMULSION_REVIEW_SAMPLES` is developed at full size and written as a
/// Display P3 JPEG, `<sample>.<look>.<label>.jpg`, into `EMULSION_REVIEW_DIR`. `Tools/review-renders.sh`
/// runs this on two commits so the pairs sit side by side; never review a look on the frozen
/// test scenes, which are 240 px. Opt-in, so CI and plain `swift test` skip it.
///
/// `EMULSION_REVIEW_INCLUDE_LOCAL=1` also renders the samples that aren't CC0, into a `local-only/`
/// subfolder: for the owner's own review, never shared or posted. `EMULSION_REVIEW_LOOK=<name>` renders
/// one look only.
///
/// Kept free of other test-target helpers: the script copies this file into an older checkout
/// when that checkout does not have it (one older than the digicam process, MOV-149, can't build it).
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
    /// The digicam process at its default amounts, and strong (more noise, full processing).
    static func digicam(noise: Double, processing: Double) -> Adjustments {
        var a = defaultLook
        (a.process, a.grain, a.halation) = (.digicam, noise, processing)
        return a
    }
    /// The film process alone, the default look, and the digicam process.
    static let looks: [(name: String, adjustments: Adjustments)] = [
        ("neutral", .neutral), ("default", defaultLook),
        ("digicam", digicam(noise: DigicamLook.defaultNoise, processing: DigicamLook.defaultProcessing)),
        ("digicam-strong", digicam(noise: 1, processing: 1)),
    ]
    /// The looks to render: all of them, or the one `EMULSION_REVIEW_LOOK` names.
    static var selectedLooks: [(name: String, adjustments: Adjustments)] {
        environment["EMULSION_REVIEW_LOOK"].map { name in looks.filter { $0.name == name } } ?? looks
    }
    static var includesLocalSamples: Bool { environment["EMULSION_REVIEW_INCLUDE_LOCAL"] == "1" }

    static func isCC0(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix("_cc0.dng") }

    /// CC0 samples, whose licence lets the renders be shared in a PR; with `includesLocalSamples`,
    /// every other DNG too.
    static func samples() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: samplesDirectory, includingPropertiesForKeys: nil)
            .filter { isCC0($0) || (includesLocalSamples && $0.pathExtension.lowercased() == "dng") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test func writesFullResolutionRenders() throws {
        let shared = try #require(Self.outputDirectory)
        let localOnly = shared.appending(path: "local-only", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let samples = try Self.samples()
        try #require(!samples.isEmpty, "no samples to render in \(Self.samplesDirectory.path)")
        let renderer = try Renderer()
        for url in samples {
            let output = Self.isCC0(url) ? shared : localOnly
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let name = url.deletingPathExtension().lastPathComponent
            let negative = try renderer.developer.develop(Data(contentsOf: url))
            for look in Self.selectedLooks {
                let rendered = try renderer.render(negative, look.adjustments, intent: .export)
                let file = output.appending(path: "\(name).\(look.name).\(Self.label).jpg")
                try renderer.export(rendered, format: .jpeg, quality: 0.95).write(to: file)
                print("\(file.lastPathComponent): \(Int(rendered.extent.width))×\(Int(rendered.extent.height))")
            }
        }
    }
}
