import Foundation
import Testing

@testable import EmulsionFit

struct FitCommandTests {
    @Test func negativeParsesEveryOption() throws {
        let command = try FitCommand(arguments: [
            "negative", "--stock", "s", "--out", "/tmp/o", "--data", "/tmp/d", "--manifests", "/tmp/m", "--standards", "/tmp/st",
            "--base", "/tmp/b.json", "--mid-gray-log-exposure", "-1.25", "--fit-date", "2026-11-10", "--name", "Warm test",
            "--bundled-default", "/tmp/default.json",
        ])
        #expect(
            command
                == .negative(
                    .init(
                        shared: .init(
                            stock: "s", out: URL(filePath: "/tmp/o", directoryHint: .isDirectory),
                            manifests: URL(filePath: "/tmp/m", directoryHint: .isDirectory),
                            data: URL(filePath: "/tmp/d", directoryHint: .isDirectory),
                            standards: URL(filePath: "/tmp/st", directoryHint: .isDirectory)),
                        base: URL(filePath: "/tmp/b.json"), midGrayLogExposure: -1.25, fitDate: "2026-11-10", name: "Warm test",
                        bundledDefault: URL(filePath: "/tmp/default.json"))))
    }

    @Test func dyesParsesEveryOption() throws {
        let command = try FitCommand(arguments: [
            "dyes", "--stock", "s", "--out", "/tmp/o", "--standards", "/tmp/st", "--data", "/tmp/d", "--manifests", "/tmp/m",
        ])
        #expect(
            command
                == .dyes(
                    .init(
                        stock: "s", out: URL(filePath: "/tmp/o", directoryHint: .isDirectory),
                        manifests: URL(filePath: "/tmp/m", directoryHint: .isDirectory),
                        data: URL(filePath: "/tmp/d", directoryHint: .isDirectory),
                        standards: URL(filePath: "/tmp/st", directoryHint: .isDirectory))))
    }

    static let badCommandLines: [([String], CommandLineError)] = [
        ([], .missingCommand),
        (["fit"], .unknownCommand("fit")),
        (["list", "--stock", "s"], .unknownOption("--stock", command: "list")),
        (["check", "--out", "o"], .unknownOption("--out", command: "check")),
        (["list", "--manifests"], .missingValue(option: "--manifests")),
        (["check", "--data"], .missingValue(option: "--data")),
        (["negative", "--stock", "--out", "o"], .missingValue(option: "--stock")),
        (["negative", "--stock", "a", "--stock", "b"], .duplicateOption("--stock")),
        (["negative", "--out", "o"], .missingOption("--stock", command: "negative")),
        (["negative", "--stock", "s"], .missingOption("--out", command: "negative")),
        (["dyes", "--stock", "s"], .missingOption("--out", command: "dyes")),
        (["dyes", "--stock", "s", "--out", "o", "--base", "b"], .unknownOption("--base", command: "dyes")),
        (
            ["negative", "--stock", "s", "--out", "o", "--mid-gray-log-exposure", "gray"],
            .invalidNumber(option: "--mid-gray-log-exposure", text: "gray")
        ),
        (["negative", "--stock", "s", "--out", "o", "--fit-date", "2026-02-30"], .invalidDate(option: "--fit-date", text: "2026-02-30")),
        (["negative", "--stock", "s", "--out", "o", "--fit-date", "10/11/2026"], .invalidDate(option: "--fit-date", text: "10/11/2026")),
    ]

    @Test(arguments: badCommandLines)
    func badCommandLineThrowsItsTypedError(_ arguments: [String], _ expected: CommandLineError) {
        #expect(throws: expected) { try FitCommand(arguments: arguments) }
    }

    @Test func listAndCheckParseDataAndManifests() throws {
        let data = URL(filePath: "/tmp/d", directoryHint: .isDirectory)
        let manifests = URL(filePath: "/tmp/m", directoryHint: .isDirectory)
        #expect(try FitCommand(arguments: ["list", "--data", "/tmp/d"]) == .list(manifests: nil, data: data))
        #expect(
            try FitCommand(arguments: ["check", "--manifests", "/tmp/m", "--data", "/tmp/d"]) == .check(manifests: manifests, data: data))
    }

    @Test func missingManifestsDirectoryIsReported() {
        #expect(throws: CommandLineError.noSuchDirectory("/no/such/emulsion-dir")) {
            try FitTool.manifestsDirectory(URL(filePath: "/no/such/emulsion-dir"))
        }
    }

    // MARK: Reference data

    static let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
    static let missingData = "/nonexistent-emulsion-data"

    @Test func referenceDataResolvesFlagThenEnvironmentThenDefault() {
        let flag = URL(filePath: "/flag", directoryHint: .isDirectory)
        let resolve = DigitizedStock.referenceDataDirectory(flag:environment:home:)
        #expect(resolve(flag, "/env", Self.home) == flag)
        #expect(resolve(nil, "/env", Self.home).path == "/env")
        let fallback = "/Users/someone/Documents/Emulsion Research/datasheet-tracings"
        #expect(resolve(nil, "", Self.home).path == fallback)
        #expect(resolve(nil, nil, Self.home).path == fallback)
    }

    @Test(arguments: [
        FitCommand.check(manifests: nil, data: nil),
        .negative(
            .init(shared: .init(stock: NegativeFitReport.targetStock, out: URL(filePath: "/tmp/unused", directoryHint: .isDirectory)))),
    ])
    func dataCommandsNeedTheReferenceData(_ command: FitCommand) {
        #expect(throws: CommandLineError.noReferenceData(Self.missingData)) {
            try FitTool.perform(command, environment: Self.missingData, home: Self.home)
        }
    }

    @Test func explicitDataThatDoesNotExistIsReported() {
        #expect(throws: CommandLineError.noSuchDirectory(Self.missingData)) {
            try FitTool.perform(
                .check(manifests: nil, data: URL(filePath: Self.missingData, directoryHint: .isDirectory)), environment: nil,
                home: Self.home)
        }
    }

    @Test func listWorksFromTheBundledManifestsAlone() throws {
        let (text, succeeded) = try FitTool.perform(.list(manifests: nil, data: nil), environment: Self.missingData, home: Self.home)
        #expect(succeeded)
        for id in StockDataTests.expectedStocks { #expect(text.contains("\(id): ")) }
        #expect(text.contains("  characteristic: red, green, blue\n"))
        let note = "(no reference data at \(Self.missingData): pass --data <dir> or set EMULSION_REFERENCE_DATA for sample counts)"
        #expect(text.components(separatedBy: note).count == 2, "\(text)")
    }

    /// One stock whose tracing doesn't match is reported; the others are still listed, and the command fails.
    @Test func listGoesOnPastAStockThatFailsToLoad() throws {
        let root = try ManifestValidationTests.Fixture(id: "a-stock", manifestStock: "a-stock").write()
        defer { try? FileManager.default.removeItem(at: root) }
        var broken = ManifestValidationTests.Fixture(id: "b-stock", manifestStock: "b-stock")
        broken.characteristicSHA256 = String(repeating: "0", count: 64)
        let brokenRoot = try broken.write()
        defer { try? FileManager.default.removeItem(at: brokenRoot) }
        try FileManager.default.moveItem(at: brokenRoot.appending(path: "b-stock"), to: root.appending(path: "b-stock"))

        let (text, succeeded) = try FitTool.perform(.list(manifests: root, data: root), environment: nil, home: Self.home)
        #expect(!succeeded)
        #expect(text.contains("a-stock: D, R\n  characteristic: red (2), green (2), blue (2)\n"), "\(text)")
        #expect(text.contains("b-stock: D, R\n  FAILED to load: "), "\(text)")
        #expect(!text.contains("no reference data"))
    }

    @Test func badCommandLineExitsWithUsageCode() {
        #expect(FitTool.main(arguments: ["fit"]) == FitTool.usageExitCode)
    }

    @Test(.enabled(if: DyeSetDataTests.available))
    func negativeWritesByteIdenticalFilesOnEveryRun() throws {
        let id = DyeSetDataTests.stock
        let runs = try (0..<2).map { _ in
            let out = FileManager.default.temporaryDirectory.appending(path: "emulsion-fit-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            let options = FitCommand.NegativeOptions(shared: .init(stock: id, out: out, standards: DyeSetDataTests.standardsDirectory))
            _ = try FitTool.perform(.negative(options))
            return try ["stock.json", "negative-fit.json", "negative-fit.csv"].map {
                try Data(contentsOf: out.appending(path: "\(id).\($0)"))
            }
        }
        #expect(runs[0] == runs[1])
    }
}
