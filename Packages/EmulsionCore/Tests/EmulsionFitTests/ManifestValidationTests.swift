import Foundation
import Testing

@testable import EmulsionFit

/// Manifest numbers are validated on load: a zero grid step or pixel scale would otherwise let the audit pass vacuously.
/// Each traced CSV must be the one its manifest pins by SHA-256.
struct ManifestValidationTests {
    /// A minimal valid stock, written to a fresh temporary directory named `id`: the manifest and its CSVs side by side,
    /// so the same directory serves as both the manifests and the reference-data folder.
    struct Fixture {
        static let csvs = [
            "characteristic.csv": "log_exposure_lux_s,red,green,blue\n-1.00,0.2,0.6,0.8\n1.00,1.2,1.6,1.8\n",
            "spectral_sensitivity.csv":
                "wavelength_nm,yellow_forming_layer,magenta_forming_layer,cyan_forming_layer\n400,1,0,0\n405,0,1,1\n",
            "spectral_dye_density.csv":
                "wavelength_nm,yellow,magenta,cyan,midscale_neutral,minimum_density\n400,1,0,0,1.5,0.5\n405,0,1,1,2.5,0.5\n",
        ]

        static func sha256(_ file: String) -> String { DigitizedChart.sha256(of: Data((csvs[file] ?? "").utf8)) }

        var id = "fixture-stock"
        var manifestStock = "fixture-stock"
        var gridStep = 0.05
        var xPixelsPerUnit = 100.0
        var yPixelsPerUnit = 100.0
        var uncertaintyY = 0.01
        var xRange: [Double] = [-1, 1]
        var interpolatedSpans: [[Double]] = []
        var stopZero = -1.3
        /// Replaces the characteristic chart's pinned digest.
        var characteristicSHA256: String?
        var writesCharacteristicCSV = true
        /// Replaces the characteristic CSV written to disk; the manifest still pins the canonical one.
        var characteristicCSV: String?

        func chart(_ file: String, gridStep: Double, curves: [String], cameraStops: Bool = false) -> [String: Any] {
            let digest = file == "characteristic.csv" ? characteristicSHA256 ?? Self.sha256(file) : Self.sha256(file)
            var chart: [String: Any] = [
                "file": file, "sha256": digest, "gridStep": gridStep, "conditions": "Densitometry: Status M",
                "xAxis": ["pixelsPerUnit": xPixelsPerUnit], "yAxis": ["pixelsPerUnit": yPixelsPerUnit],
                "uncertainty": ["x": 0.01, "y": uncertaintyY, "note": ""],
                "curves": Dictionary(
                    uniqueKeysWithValues: curves.map { ($0, ["xRange": xRange, "interpolatedSpans": interpolatedSpans] as [String: Any]) }),
            ]
            if cameraStops { chart["cameraStops"] = ["stopZeroLogExposure": stopZero] }
            return chart
        }

        func write() throws -> URL {
            let root = FileManager.default.temporaryDirectory.appending(path: "emulsion-fit-\(UUID().uuidString)")
            let directory = root.appending(path: id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "formatVersion": 1, "stock": manifestStock, "filmType": "cameraNegative",
                "source": ["publisher": "P", "document": "D", "title": "T", "revision": "R", "url": "u", "pdfSHA256": "0"],
                "charts": [
                    "characteristic": chart(
                        "characteristic.csv", gridStep: gridStep, curves: ["red", "green", "blue"], cameraStops: true),
                    "spectralSensitivity": chart(
                        "spectral_sensitivity.csv", gridStep: 5,
                        curves: ["yellow_forming_layer", "magenta_forming_layer", "cyan_forming_layer"]),
                    "spectralDyeDensity": chart(
                        "spectral_dye_density.csv", gridStep: 5,
                        curves: ["yellow", "magenta", "cyan", "midscale_neutral", "minimum_density"]),
                ],
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appending(path: "manifest.json"))
            for (name, text) in Self.csvs where writesCharacteristicCSV || name != "characteristic.csv" {
                let written = name == "characteristic.csv" ? characteristicCSV ?? text : text
                try Data(written.utf8).write(to: directory.appending(path: name))
            }
            return root
        }

        /// Loads the fixture; returns the error, or nil when it loads.
        func loadError() throws -> FitError? {
            let root = try write()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                _ = try DigitizedStock.load(id: id, from: root, referenceData: root)
                return nil
            } catch {
                return error
            }
        }

        /// Loads the fixture; returns the `invalidManifest` reason, or nil when it loads.
        func loadFailure() throws -> String? {
            guard let error = try loadError() else { return nil }
            guard case .invalidManifest(_, let reason) = error else { throw error }
            return reason
        }
    }

    @Test func validFixtureLoads() throws {
        #expect(try Fixture().loadFailure() == nil)
    }

    @Test func tracingThatDiffersFromItsManifestIsRejected() throws {
        var fixture = Fixture()
        let pinned = String(repeating: "0", count: 64)
        fixture.characteristicSHA256 = pinned
        let error = try #require(try fixture.loadError())
        guard case .tracingMismatch(let file, let expected, let found) = error else {
            Issue.record("expected tracingMismatch, got \(error)")
            return
        }
        #expect(file.hasSuffix("fixture-stock/characteristic.csv"))
        #expect(expected == pinned)
        #expect(found == Fixture.sha256("characteristic.csv"))
    }

    /// The digest is checked before parsing, so a different file is a mismatch even when it wouldn't parse.
    @Test func unparsableTracingWithTheWrongDigestIsAMismatch() throws {
        var fixture = Fixture()
        let csv = (Fixture.csvs["characteristic.csv"] ?? "") + "2.00,not-a-number\n"
        fixture.characteristicCSV = csv
        let error = try #require(try fixture.loadError())
        guard case .tracingMismatch(_, let expected, let found) = error else {
            Issue.record("expected tracingMismatch, got \(error)")
            return
        }
        #expect(expected == Fixture.sha256("characteristic.csv"))
        #expect(found == DigitizedChart.sha256(of: Data(csv.utf8)))
    }

    @Test func missingTracingIsReportedWithItsPath() throws {
        var fixture = Fixture()
        fixture.writesCharacteristicCSV = false
        let error = try #require(try fixture.loadError())
        guard case .missingFile(let path) = error else {
            Issue.record("expected missingFile, got \(error)")
            return
        }
        #expect(path.hasSuffix("fixture-stock/characteristic.csv"))
        #expect(error.errorDescription?.contains(DigitizedStock.referenceDataEnvironmentVariable) == true)
    }

    @Test(arguments: ["abc", String(repeating: "A", count: 64), String(repeating: "g", count: 64)])
    func malformedDigestIsRejected(_ digest: String) throws {
        var fixture = Fixture()
        fixture.characteristicSHA256 = digest
        let reason = try #require(try fixture.loadFailure())
        #expect(reason.contains("charts.characteristic.sha256"), "\(reason)")
    }

    static let badNumbers: [(String, @Sendable (inout Fixture) -> Void)] = [
        ("gridStep", { $0.gridStep = 0 }),
        ("gridStep", { $0.gridStep = -0.05 }),
        ("xAxis.pixelsPerUnit", { $0.xPixelsPerUnit = 0 }),
        ("yAxis.pixelsPerUnit", { $0.yPixelsPerUnit = 0 }),
        ("uncertainty.y", { $0.uncertaintyY = -0.01 }),
        ("xRange", { $0.xRange = [1, -1] }),
        ("xRange", { $0.xRange = [0] }),
        ("spans", { $0.interpolatedSpans = [[0.5, 0.2]] }),
    ]

    @Test(arguments: badNumbers.indices)
    func unusableManifestNumberIsRejectedByName(_ index: Int) throws {
        let (field, edit) = Self.badNumbers[index]
        var fixture = Fixture()
        edit(&fixture)
        let reason = try #require(try fixture.loadFailure())
        #expect(reason.contains(field), "\(reason)")
    }

    @Test func manifestStockMustMatchItsDirectory() throws {
        var fixture = Fixture()
        fixture.manifestStock = "another-stock"
        let reason = try #require(try fixture.loadFailure())
        #expect(reason.contains("another-stock") && reason.contains("fixture-stock"))
    }

    /// JSON can't carry a non-finite number, so this one is checked on a manifest built in code.
    @Test func nonFiniteCameraStopAnchorIsAProblem() {
        let chart = StockManifest.Chart(
            file: "c.csv", sha256: String(repeating: "0", count: 64), gridStep: 0.05, conditions: "", xAxis: .init(pixelsPerUnit: 1),
            yAxis: .init(pixelsPerUnit: 1),
            uncertainty: .init(x: 0, y: 0, note: ""), curves: [:], cameraStops: .init(stopZeroLogExposure: .nan))
        let manifest = StockManifest(
            formatVersion: 1, stock: "s", filmType: .cameraNegative,
            source: .init(publisher: "", document: "", title: "", revision: "", url: "", pdfSHA256: ""),
            charts: ["characteristic": chart])
        #expect(manifest.problems == ["charts.characteristic.cameraStops.stopZeroLogExposure must be finite."])
    }
}
