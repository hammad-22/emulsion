import Foundation
import Testing

@testable import EmulsionFit

/// Manifest checks always run. Checks on the traced curves, which are not in the repository (docs/DECISIONS.md,
/// 12 Nov 2026), run only when the local reference-data folder exists (`EMULSION_REFERENCE_DATA`, else the default).
struct StockDataTests {
    static let expectedStocks = ["kodak-vision-2383", "kodak-vision3-250d-5207", "kodak-vision3-500t-5219"]
    static let manifestsDirectory = DigitizedStock.bundledManifestsDirectory
    static let referenceDataDirectory = DigitizedStock.referenceDataDirectory
    static let referenceDataAvailable = referenceDataDirectory.isExistingDirectory
    static let presentStocks = manifestsDirectory.map(DigitizedStock.availableIDs(in:)) ?? []

    /// Datasheet PDFs as recorded in docs/STOCK-DATA.md: stock id → (document, SHA-256).
    static let sheets: [String: (document: String, sha256: String)] = [
        "kodak-vision3-250d-5207": ("H-1-5207", "70adb298a7aabb285d986b720e07c87c27eb2361f0925aea2b15903c08282e16"),
        "kodak-vision3-500t-5219": ("H-1-5219", "6d037d8090373ee50d10bedfff3df14777a575dd107c50edcafc7ec5862d0972"),
        "kodak-vision-2383": ("H-1-2383", "a72fa4482ebd891a9ac4a823cafe740e3587c56470f27e4dfd4391f5c3e5a207"),
    ]

    /// Present stocks of one film type, as their manifests declare it.
    static func stocks(_ filmType: StockManifest.FilmType) -> [String] {
        presentStocks.filter { id in manifestsDirectory.flatMap { try? StockManifest.load(id: id, from: $0) }?.filmType == filmType }
    }

    static func manifest(_ id: String) throws -> StockManifest {
        try StockManifest.load(id: id, from: #require(manifestsDirectory))
    }

    static func load(_ id: String) throws -> DigitizedStock {
        try DigitizedStock.load(id: id, from: #require(manifestsDirectory), referenceData: referenceDataDirectory)
    }

    // MARK: Committed manifests

    @Test func everyDigitizedStockIsBundled() {
        #expect(Self.presentStocks == Self.expectedStocks)
    }

    @Test(arguments: presentStocks)
    func manifestLoadsAndValidates(_ id: String) throws {
        let manifest = try Self.manifest(id)
        #expect(manifest.stock == id)
        #expect(Set(manifest.charts.keys) == Set(DigitizedChart.Kind.allCases.map(\.rawValue)))
    }

    @Test func noTracedCurveIsBundled() throws {
        let directory = try #require(Self.manifestsDirectory)
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let csvs = files.compactMap { ($0 as? URL)?.lastPathComponent }.filter { $0.lowercased().hasSuffix(".csv") }
        #expect(csvs.isEmpty, "Traced datasheet curves stay out of the repository until the MOV-94 review (docs/DECISIONS.md).")
    }

    @Test(arguments: presentStocks)
    func manifestNamesTheArchivedDatasheet(_ id: String) throws {
        let sheet = try #require(Self.sheets[id])
        let source = try Self.manifest(id).source
        #expect(source.document == sheet.document)
        #expect(source.pdfSHA256 == sheet.sha256)
    }

    @Test(arguments: presentStocks)
    func onlyCameraNegativesHaveACameraStopAxis(_ id: String) throws {
        let manifest = try Self.manifest(id)
        let characteristic = try #require(manifest.charts[DigitizedChart.Kind.characteristic.rawValue])
        #expect((characteristic.cameraStops != nil) == (manifest.filmType == .cameraNegative))
    }

    // MARK: Local reference data

    @Test(.enabled(if: referenceDataAvailable), arguments: presentStocks)
    func allChartsLoad(_ id: String) throws {
        let stock = try Self.load(id)
        #expect(stock.characteristic.curves.map(\.name) == ["red", "green", "blue"])
        #expect(stock.spectralSensitivity.curves.count == 3)
        #expect(stock.spectralDyeDensity.curves.count >= 4)
        #expect(stock.manifest.stock == id)
    }

    @Test(.enabled(if: referenceDataAvailable), arguments: presentStocks)
    func samplesLieOnTheDigitizingGrid(_ id: String) throws {
        let stock = try Self.load(id)
        for chart in stock.charts { #expect(StockDataAudit.offGrid(chart) == []) }
        #expect(stock.characteristic.entry.gridStep == 0.05)
        #expect(stock.spectralSensitivity.entry.gridStep == 5 && stock.spectralDyeDensity.entry.gridStep == 5)
    }

    @Test(.enabled(if: referenceDataAvailable), arguments: presentStocks)
    func characteristicCurvesNeverFallBeyondTracingTolerance(_ id: String) throws {
        #expect(try StockDataAudit.falling(Self.load(id).characteristic) == [])
    }

    @Test(.enabled(if: referenceDataAvailable), arguments: presentStocks)
    func samplesStayInsideTheTracedRange(_ id: String) throws {
        for chart in try Self.load(id).charts { #expect(StockDataAudit.outsideTracedRange(chart) == []) }
    }

    // MARK: Dye sum (MOV-17)

    @Test(.enabled(if: referenceDataAvailable), arguments: presentStocks)
    func dyesSumToTheNeutral(_ id: String) throws {
        let stock = try Self.load(id)
        let check = try #require(DyeSumCheck.acceptance(stock.spectralDyeDensity, filmType: stock.manifest.filmType))
        #expect(check.scales.allSatisfy { $0 >= 0 })
        #expect(check.comparison.subtractsMinimumDensity == (stock.manifest.filmType == .cameraNegative))
        #expect(check.maxAbsResidual <= DyeSumCheck.targetMaxResidual)
    }

    @Test func dyeSumScalesAreNonNegativeAndExact() throws {
        let chart = try Self.dyeChart(
            """
            wavelength_nm,yellow,magenta,cyan,visual_neutral
            400,1,0,0,0.5
            405,0,1,0,2
            410,0,0,1,-1
            415,1,1,1,1.5
            """)
        let check = try #require(DyeSumCheck.compared(chart, .init()))
        // With cyan clamped at 0, yellow and magenta solve their own normal equations: [[2,1],[1,2]]·a = [2, 3.5].
        #expect(abs(check.scales[0] - 1.0 / 6) < 1e-12)
        #expect(abs(check.scales[1] - 5.0 / 3) < 1e-12)
        #expect(check.scales[2] == 0)
        #expect(check.neutral == "visual_neutral")
        let unit = try #require(DyeSumCheck.compared(chart, .init(fixedScales: [1, 1, 1])))
        #expect(unit.residuals == [-0.5, 1, -2, -1.5])
        #expect(unit.meanResidual == -0.75)
        #expect(unit.wavelengthOfMax == 410)
    }

    @Test func printFilmAcceptanceKeepsTheImageDyeWavelengths() throws {
        let chart = try Self.dyeChart(
            """
            wavelength_nm,yellow,magenta,cyan,visual_neutral
            395,1,0,0,9
            400,1,0,0,1
            700,0,1,0,2
            705,0,0,1,9
            """)
        let check = try #require(DyeSumCheck.acceptance(chart, filmType: .printFilm))
        #expect(check.wavelengths == [400, 700])
        #expect(check.maxAbsResidual < 1e-12)
        #expect(DyeSumCheck.diagnostics(chart, filmType: .printFilm).map(\.label) == ["full overlap", "scales = 1, 400–700"])
    }

    @Test func negativeAcceptanceSubtractsTheMinimumDensity() throws {
        let chart = try Self.dyeChart(
            """
            wavelength_nm,yellow,magenta,cyan,midscale_neutral,minimum_density
            400,1,0,0,1.5,0.5
            405,0,-0.1,1,1.3,0.4
            410,0,1,0,1.6,0.6
            """)
        let check = try #require(DyeSumCheck.acceptance(chart, filmType: .cameraNegative))
        #expect(check.comparison.subtractsMinimumDensity)
        #expect(check.maxAbsResidual < 1e-12)
        #expect(zip(check.scales, [1.0, 1, 1]).allSatisfy { abs($0 - $1) < 1e-12 })
        #expect(DyeSumCheck.diagnostics(chart, filmType: .cameraNegative).map(\.label) == ["neutral, Dmin kept"])
    }

    // MARK: CSV parser

    @Test func emptyCellsDropOnlyThatCurvesRow() throws {
        let curves = try DigitizedChart.parse(
            "x,a,b\n1,0.5,\n2,,0.25\n3,0.75,1\n", acceptedHeaders: [["x", "a", "b"]], file: "t.csv")
        #expect(curves == [DigitizedCurve(name: "a", x: [1, 3], y: [0.5, 0.75]), DigitizedCurve(name: "b", x: [2, 3], y: [0.25, 1])])
    }

    @Test func wrongHeaderIsRejected() {
        #expect(throws: FitError.badHeader(file: "t.csv", expected: [["x", "a"]], found: ["x", "b"])) {
            try DigitizedChart.parse("x,b\n1,2\n", acceptedHeaders: [["x", "a"]], file: "t.csv")
        }
    }

    @Test(arguments: ["abc", "nan", "inf", "1.2.3"])
    func nonNumericCellIsRejectedWithItsLine(_ text: String) {
        #expect(throws: FitError.nonNumericCell(file: "t.csv", line: 3, column: "a", text: text)) {
            try DigitizedChart.parse("x,a\n1,2\n2,\(text)\n", acceptedHeaders: [["x", "a"]], file: "t.csv")
        }
    }

    @Test(arguments: ["1,2\n1,3\n", "1,2\n0.5,3\n"])
    func nonAscendingXIsRejected(_ rows: String) {
        #expect {
            try DigitizedChart.parse("x,a\n" + rows, acceptedHeaders: [["x", "a"]], file: "t.csv")
        } throws: { error in
            guard case .nonAscendingX(_, let line, _, _) = error as? FitError else { return false }
            return line == 3
        }
    }

    @Test func missingCellIsRejected() {
        #expect(throws: FitError.wrongCellCount(file: "t.csv", line: 2, expected: 3, found: 2)) {
            try DigitizedChart.parse("x,a,b\n1,2\n", acceptedHeaders: [["x", "a", "b"]], file: "t.csv")
        }
    }

    @Test func curveWithoutValuesIsRejected() {
        #expect(throws: FitError.emptyCurve(file: "t.csv", column: "b")) {
            try DigitizedChart.parse("x,a,b\n1,2,\n", acceptedHeaders: [["x", "a", "b"]], file: "t.csv")
        }
    }

    @Test func unknownStockListsTheAvailableOnes() throws {
        let directory = try #require(Self.manifestsDirectory)
        #expect(throws: FitError.unknownStock("no-such-stock", available: Self.presentStocks)) {
            try DigitizedStock.load(id: "no-such-stock", from: directory, referenceData: directory)
        }
    }

    static func dyeChart(_ csv: String) throws -> DigitizedChart {
        let entry = StockManifest.Chart(
            file: "spectral_dye_density.csv", sha256: String(repeating: "0", count: 64), gridStep: 5, conditions: "",
            xAxis: .init(pixelsPerUnit: 1), yAxis: .init(pixelsPerUnit: 1),
            uncertainty: .init(x: 0, y: 0, note: ""), curves: [:], cameraStops: nil)
        return try DigitizedChart(kind: .spectralDyeDensity, entry: entry, file: "t.csv", data: Data(csv.utf8))
    }
}
