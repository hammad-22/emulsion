import Foundation
import Testing

@testable import EmulsionCore

/// Look-review renders (MOV-146): see Tests/AGENTS.md, "Perceptual checks"; opt-in.
/// Uses no other test helpers: Tools/review-renders.sh copies it into older checkouts.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_REVIEW_DIR"] != nil), .serialized)
struct ReviewRenders {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var outputDirectory: URL? { environment["EMULSION_REVIEW_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
    static var label: String { environment["EMULSION_REVIEW_LABEL"] ?? "render" }
    static var samplesDirectory: URL {
        environment["EMULSION_REVIEW_SAMPLES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL.homeDirectory.appending(path: "Documents/Emulsion Research/samples/proraw-misc")
    }

    /// A fixed grain seed, so a pair differs only by the engine.
    static let defaultLook: Adjustments = {
        var a = Adjustments()
        a.seed = 7
        return a
    }()
    static func digicam(noise: Double, processing: Double) -> Adjustments {
        var a = defaultLook
        (a.process, a.grain, a.halation) = (.digicam, noise, processing)
        return a
    }
    static let looks: [(name: String, adjustments: Adjustments)] = [
        ("neutral", .neutral), ("default", defaultLook),
        ("digicam", digicam(noise: DigicamLook.defaultNoise, processing: DigicamLook.defaultProcessing)),
        ("digicam-strong", digicam(noise: 1, processing: 1)),
    ]
    static var selectedLooks: [(name: String, adjustments: Adjustments)] {
        environment["EMULSION_REVIEW_LOOK"].map { name in looks.filter { $0.name == name } } ?? looks
    }
    static var includesLocalSamples: Bool { environment["EMULSION_REVIEW_INCLUDE_LOCAL"] == "1" }

    static func isCC0(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix("_cc0.dng") }

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
