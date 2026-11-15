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

    static func digicam(noise: Double, processing: Double) -> Adjustments {
        var a = Adjustments()
        (a.process, a.grain, a.halation) = (.digicam, noise, processing)
        return a
    }
    static let looks: [(name: String, adjustments: Adjustments)] = [
        ("neutral", .neutral), ("default", Adjustments()),
        ("digicam", digicam(noise: DigicamLook.defaultNoise, processing: DigicamLook.defaultProcessing)),
        ("digicam-strong", digicam(noise: 1, processing: 1)),
    ]
    static var selectedLooks: [(name: String, adjustments: Adjustments)] {
        environment["EMULSION_REVIEW_LOOK"].map { name in looks.filter { $0.name == name } } ?? looks
    }
    static var includesLocalSamples: Bool { environment["EMULSION_REVIEW_INCLUDE_LOCAL"] == "1" }

    /// Seeds the app can give a photo (EmulsionKit's `Adjustments.grainSeedCount`).
    static let seedCount: UInt32 = 1024

    /// A grain seed per file, as the app gives each photo its own: the same file gets the same seed in both renders of a
    /// pair, so a pair differs only by the engine, while different files show different grain (FNV-1a of the name).
    static func seed(for name: String) -> Double {
        let hash = name.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return Double(hash % seedCount)
    }

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
                var adjustments = look.adjustments
                adjustments.seed = Self.seed(for: name)
                let rendered = try renderer.render(negative, adjustments, intent: .export)
                let file = output.appending(path: "\(name).\(look.name).\(Self.label).jpg")
                try renderer.export(rendered, format: .jpeg, quality: 0.95).write(to: file)
                print("\(file.lastPathComponent): \(Int(rendered.extent.width))×\(Int(rendered.extent.height))")
            }
        }
    }
}
