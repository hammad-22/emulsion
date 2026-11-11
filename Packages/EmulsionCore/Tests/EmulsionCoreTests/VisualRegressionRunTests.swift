import Foundation
import Testing

/// The regression harness itself, run on tiny synthetic images in a temporary directory that is
/// both the golden store and the report directory.
struct VisualRegressionRunTests {
    private struct RenderFailure: Error {}

    private static let image = RegressionImage(width: 2, height: 1, pixels: [SIMD3(repeating: 30000), SIMD3(repeating: 40000)])

    private static func item(_ name: String) -> VisualRegression.Item { VisualRegression.Item(name: name) { image } }

    private static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "visual-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func run(_ items: [VisualRegression.Item], in directory: URL, mode: VisualRegression.UpdateMode = .none) throws {
        try VisualRegression.run(
            "test", items, store: .local(directory), reportDirectory: directory, regenerate: "regenerate", mode: mode, isCI: false,
            writesAllImages: false)
    }

    private static func statuses(in directory: URL) throws -> [String] {
        let data = try Data(contentsOf: directory.appending(path: "report.json"))
        return try JSONDecoder().decode(VisualRegression.Report.self, from: data).cases.map(\.status.rawValue)
    }

    @Test func prepareRemovesOnlyFilesTheSuiteWrites() throws {
        try Self.withTemporaryDirectory { directory in
            let images = directory.appending(path: "images")
            try FileManager.default.createDirectory(at: images.appending(path: "nested"), withIntermediateDirectories: true)
            let foreign = ["images/keep.txt", "images/photo.png", "notes.md"]
            let stale = ["report.md", "report.json", "update-summary.md", "images/x.actual.png", "images/nested/y.diff.png"]
            for name in foreign + stale { try Data("x".utf8).write(to: directory.appending(path: name)) }

            try ReportFiles(directory: directory).prepare()

            for name in foreign { #expect(FileManager.default.fileExists(atPath: directory.appending(path: name).path), "\(name) removed") }
            for name in stale { #expect(!FileManager.default.fileExists(atPath: directory.appending(path: name).path), "\(name) kept") }
        }
    }

    @Test func aThrowingRenderIsReportedAndTheRunContinues() throws {
        try Self.withTemporaryDirectory { directory in
            let store = VisualRegression.Store.local(directory)
            for name in ["a", "c"] { try VisualRegression.write(Self.image, to: store.writeURL(name)) }
            let items = [Self.item("a"), VisualRegression.Item(name: "b") { throw RenderFailure() }, Self.item("c")]

            withKnownIssue { try Self.run(items, in: directory) }
            #expect(try Self.statuses(in: directory) == ["pass", "error", "pass"])

            withKnownIssue { try Self.run(items, in: directory, mode: .failing) }
            #expect(try Self.statuses(in: directory) == ["unchanged", "error", "unchanged"])
            #expect(!FileManager.default.fileExists(atPath: store.writeURL("b").path))
        }
    }

    @Test func anUnreadableGoldenFailsAndIsRewrittenOnUpdate() throws {
        try Self.withTemporaryDirectory { directory in
            try Data("not a png".utf8).write(to: VisualRegression.Store.local(directory).writeURL("a"))

            try withKnownIssue {
                try Self.run([Self.item("a")], in: directory)
            } matching: { issue in
                issue.comments.contains { $0.rawValue.contains("unreadable golden") && $0.rawValue.contains("regenerate") }
            }
            #expect(try Self.statuses(in: directory) == ["fail"])

            try Self.run([Self.item("a")], in: directory, mode: .failing)
            #expect(try Self.statuses(in: directory) == ["changed"])

            try Self.run([Self.item("a")], in: directory)
            #expect(try Self.statuses(in: directory) == ["pass"])
        }
    }

    @Test func updateSummaryCountsRewrittenGoldens() throws {
        try Self.withTemporaryDirectory { directory in
            try VisualRegression.write(Self.image, to: VisualRegression.Store.local(directory).writeURL("a"))

            try Self.run([Self.item("a")], in: directory, mode: .all)

            let summary = try String(contentsOf: directory.appending(path: "update-summary.md"), encoding: .utf8)
            #expect(summary.contains("1 of 1 goldens rewritten (0 new or changed)."), "\(summary)")
        }
    }
}
