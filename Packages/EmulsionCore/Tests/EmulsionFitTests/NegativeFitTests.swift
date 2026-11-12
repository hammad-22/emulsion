import EmulsionCore
import Foundation
import Testing

@testable import EmulsionFit

struct NegativeFitTests {
    /// The 250D chart's log10 exposure axis, −3.7…1.1 on the 0.05 grid.
    static let logExposures = (0...96).map { -3.7 + Double($0) * 0.05 }
    static let midGray = -1.3
    static let truth = [
        NegativeFit.LayerCurve(minimumDensity: 0.25, gamma: 0.55, densityRange: 2.2, exposureOffset: 0.3),
        NegativeFit.LayerCurve(minimumDensity: 0.6, gamma: 0.62, densityRange: 2.5, exposureOffset: 0.1),
        NegativeFit.LayerCurve(minimumDensity: 0.85, gamma: 0.68, densityRange: 2.8, exposureOffset: -0.2),
    ]

    static func truth(_ parameterization: NegativeFit.Parameterization) -> [NegativeFit.LayerCurve] {
        parameterization == .perLayerRange
            ? truth
            : truth.map {
                var layer = $0
                layer.densityRange = 2.5
                return layer
            }
    }

    /// Curves drawn from known parameters through the model itself, plus optional Gaussian noise.
    static func synthetic(_ parameterization: NegativeFit.Parameterization, noise: Double) -> NegativeFit {
        var random = DeterministicGaussian(seed: 0x5EED)
        let template = NegativeFit(curves: [], midGrayLogExposure: midGray, parameterization: parameterization)
        let curves = zip(NegativeFit.Layer.allCases, truth(parameterization)).map { layer, curve in
            DigitizedCurve(
                name: layer.rawValue, x: logExposures,
                y: logExposures.map { template.density(curve, logExposure: $0) + noise * random.next() })
        }
        return NegativeFit(curves: curves, midGrayLogExposure: midGray, parameterization: parameterization)
    }

    @Test(arguments: NegativeFit.Parameterization.allCases)
    func noiseFreeCurvesGiveBackTheirParameters(_ parameterization: NegativeFit.Parameterization) {
        let model = Self.synthetic(parameterization, noise: 0)
        let result = model.solve()
        #expect(result.termination.converged)
        let expected = model.parameters(Self.truth(parameterization))
        for (name, (fitted, value)) in zip(model.parameterNames, zip(result.parameters, expected)) {
            #expect(abs(fitted - value) <= 1e-6, "\(name)")
        }
    }

    @Test(arguments: NegativeFit.Parameterization.allCases)
    func noisyCurvesLandWithinAFewStandardErrors(_ parameterization: NegativeFit.Parameterization) throws {
        let model = Self.synthetic(parameterization, noise: 0.01)
        let result = model.solve()
        #expect(result.termination.converged)
        #expect(abs(result.rms - 0.01) < 0.002)
        let expected = model.parameters(Self.truth(parameterization))
        for (index, name) in model.parameterNames.enumerated() {
            let error = try #require(result.standardErrors[index], "\(name)")
            #expect(abs(result.parameters[index] - expected[index]) <= 4 * error, "\(name)")
        }
    }

    // MARK: Real data

    static let negatives = StockDataTests.stocks(.cameraNegative)
    static let hasData = StockDataTests.referenceDataAvailable

    /// Each camera negative fitted once from the local reference data, shared by the tests below.
    static let reports: [String: NegativeFitReport] =
        hasData
        ? negatives.reduce(into: [:]) { reports, id in
            reports[id] = try? NegativeFitReport.fitting(StockDataTests.load(id), tool: FitTool.toolName)
        } : [:]

    static func report(_ id: String) throws -> NegativeFitReport {
        try #require(reports[id], "\(id) didn't load or fit; run `emulsion-fit negative --stock \(id)` for the error")
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func realFitsConverge(_ id: String) throws {
        let report = try Self.report(id)
        #expect(report.fits.map(\.parameterization) == NegativeFit.Parameterization.allCases)
        for fit in report.fits { #expect(fit.optimizer.converged, "\(fit.parameterization)") }
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func reportedRMSMatchesItsSampleTable(_ id: String) throws {
        let report = try Self.report(id)
        for fit in report.fits {
            let residuals = fit.samples.map { $0.measured - $0.fitted }
            let rms = (residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)).squareRoot()
            #expect(abs(rms - fit.overall.rms) <= 1e-12)
            for layer in fit.layers {
                let own = fit.samples.filter { $0.layer == layer.layer }.map { $0.measured - $0.fitted }
                #expect(abs((own.reduce(0) { $0 + $1 * $1 } / Double(own.count)).squareRoot() - layer.statistics.rms) <= 1e-12)
            }
        }
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func fittedStockPassesTheEngine(_ id: String) throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let stock = try FittedStock.make(base: base, report: Self.report(id), fitDate: nil)
        _ = try FilmModel(stock: FilmStock(data: stock.encoded()))
        #expect(stock.provenance.fitDate == nil)
        #expect(stock.provenance.sourceSHA256 == (try StockDataTests.load(id)).characteristic.sha256)
        #expect(stock.print == base.print && stock.rendering == base.rendering && stock.negative.sensitivity == base.negative.sensitivity)
    }

    @Test(.enabled(if: hasData && negatives.contains(NegativeFitReport.targetStock)))
    func sharedRangeFitMeetsTheTargetOnItsStock() throws {
        let report = try Self.report(NegativeFitReport.targetStock)
        let rms = try #require(report.fit(.sharedRange)).overall.rms
        #expect(rms < NegativeFitReport.targetRMS)
        #expect(report.sharedRangeMeetsTarget == true)
    }

    /// The RMS target is MOV-106's for one stock; others are compared with it, never judged by it.
    @Test(.enabled(if: hasData), arguments: negatives.filter { $0 != NegativeFitReport.targetStock })
    func otherStocksGetNoTargetVerdict(_ id: String) throws {
        let report = try Self.report(id)
        #expect(report.sharedRangeMeetsTarget == nil)
        let summary = NegativeFitSummary.text(report)
        #expect(summary.contains("target is set for \(NegativeFitReport.targetStock) only"))
        #expect(!summary.contains(": met") && !summary.contains(": missed"))
    }

    /// The display name never carries the datasheet's id or publisher; provenance does (MOV-92).
    @Test(.enabled(if: hasData), arguments: negatives)
    func fittedStockNameCarriesNoSourceName(_ id: String) throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let report = try Self.report(id)
        let stock = try FittedStock.make(base: base, report: report, fitDate: nil)
        #expect(stock.name == "\(base.name), fitted negative")
        #expect(!stock.name.contains(id) && !stock.name.contains(report.source.publisher))
        #expect(stock.provenance.source.contains(report.source.publisher))
    }

    @Test(.enabled(if: hasData && !negatives.isEmpty))
    func nameOptionIsWrittenToTheStockFile() throws {
        let id = try #require(Self.negatives.first)
        let out = FileManager.default.temporaryDirectory.appending(path: "emulsion-fit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        _ = try FitTool.perform(.negative(.init(stock: id, out: out, name: "Warm test")))
        let written = try FilmStock(data: Data(contentsOf: out.appending(path: "\(id).stock.json")))
        #expect(written.name == "Warm test")
    }

    /// Counted again straight from manifest.json, independent of the decoder and the report.
    @Test(.enabled(if: hasData), arguments: negatives)
    func interpolatedSampleCountMatchesTheManifestSpans(_ id: String) throws {
        let directory = try #require(StockDataTests.manifestsDirectory)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "\(id)/manifest.json")))
        let curves = try #require(((json as? [String: Any])?["charts"] as? [String: Any])?["characteristic"] as? [String: Any])
        let extents = try #require(curves["curves"] as? [String: [String: Any]])
        for fit in try Self.report(id).fits {
            for layer in fit.layers {
                let extent = try #require(extents[layer.layer.rawValue])
                let spans = ((extent["interpolatedSpans"] as? [[Double]]) ?? []) + ((extent["sharedSpans"] as? [[Double]]) ?? [])
                let expected = fit.samples.filter { sample in
                    sample.layer == layer.layer && spans.contains { $0[0] <= sample.logExposure && sample.logExposure <= $0[1] }
                }.count
                #expect(layer.interpolatedSampleCount == expected, "\(layer.layer)")
            }
        }
    }

    @Test(.enabled(if: hasData), arguments: StockDataTests.stocks(.printFilm))
    func printFilmIsNotFittedAsANegative(_ id: String) throws {
        #expect(throws: NegativeFitError.notACameraNegative(id)) {
            try NegativeFitReport.fitting(StockDataTests.load(id), tool: FitTool.toolName)
        }
    }

    // MARK: Committed fitted stocks

    /// Parameters and provenance only; the fit report and plot table hold traced samples and stay local.
    static func committedStock(_ id: String) throws -> Data {
        let directory = try #require(StockDataTests.manifestsDirectory)
        return try Data(contentsOf: directory.appending(path: "\(id)/\(FittedStock.committedFileName)"))
    }

    @Test(arguments: negatives)
    func committedFittedStockPassesTheEngineAndNamesItsTracing(_ id: String) throws {
        let stock = try FilmStock(data: Self.committedStock(id))
        _ = try FilmModel(stock: stock)
        let characteristic = try #require(StockDataTests.manifest(id).charts[DigitizedChart.Kind.characteristic.rawValue])
        #expect(stock.provenance.sourceSHA256 == characteristic.sha256)
        #expect(stock.provenance.fitResiduals?.isEmpty == false)
        let name = stock.name.lowercased()
        for word in ["kodak", "vision", "5207", "5219"] { #expect(!name.contains(word), "\(stock.name)") }
    }

    @Test(arguments: StockDataTests.stocks(.printFilm))
    func printFilmHasNoFittedStock(_ id: String) throws {
        let directory = try #require(StockDataTests.manifestsDirectory)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "\(id)/\(FittedStock.committedFileName)").path))
    }

    /// The committed file is what `emulsion-fit negative --fit-date 2026-11-12` writes from the pinned tracing.
    @Test(.enabled(if: hasData), arguments: negatives)
    func refittingReproducesTheCommittedStock(_ id: String) throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let stock = try FittedStock.make(base: base, report: Self.report(id), fitDate: "2026-11-12")
        #expect(try stock.encoded() == Self.committedStock(id))
    }
}

/// Box–Muller over a 64-bit LCG (Knuth's MMIX constants): the same seed gives the same noise on every run.
struct DeterministicGaussian {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    private mutating func uniform() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }

    mutating func next() -> Double {
        (-2 * log(uniform())).squareRoot() * cos(2 * Double.pi * uniform())
    }
}
