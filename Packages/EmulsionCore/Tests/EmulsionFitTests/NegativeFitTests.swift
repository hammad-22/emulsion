import EmulsionCore
import Foundation
import Testing
import simd

@testable import EmulsionFit

struct NegativeFitTests {
    /// The 250D chart's log10 exposure axis relative to mid-gray (−3.7…1.1 log lux·s, mid-gray −1.3), on the 0.05 grid.
    static let logExposures = (0...96).map { -2.4 + Double($0) * 0.05 }
    /// Near what 250D's dye amounts give: offset, gamma, toe, toe width, shoulder, shoulder width.
    static let toeShoulderTruth = [0.01, 0.52, -1.45, 0.25, 2.1, 0.38]
    static let logisticTruth = [-0.18, 0.56, 2.2, 0.3]

    static func truth(_ form: NegativeCurveForm) -> [Double] { form == .toeShoulder ? toeShoulderTruth : logisticTruth }

    /// A curve drawn from known parameters through the form itself, plus optional Gaussian noise.
    static func synthetic(_ form: NegativeCurveForm, noise: Double) -> NegativeFit {
        var random = DeterministicGaussian(seed: 0x5EED)
        let y = logExposures.map { form.dyeAmount(truth(form), at: $0) + noise * random.next() }
        return NegativeFit(curve: DigitizedCurve(name: form.rawValue, x: logExposures, y: y), form: form)
    }

    @Test(arguments: NegativeCurveForm.allCases)
    func noiseFreeCurvesGiveBackTheirParameters(_ form: NegativeCurveForm) {
        let result = Self.synthetic(form, noise: 0).solve()
        #expect(result.termination.converged)
        for (name, (fitted, value)) in zip(form.parameterNames, zip(result.parameters, Self.truth(form))) {
            #expect(abs(fitted - value) <= 1e-6, "\(name)")
        }
    }

    @Test(arguments: NegativeCurveForm.allCases)
    func noisyCurvesLandWithinAFewStandardErrors(_ form: NegativeCurveForm) throws {
        let result = Self.synthetic(form, noise: 0.005).solve()
        #expect(result.termination.converged)
        #expect(abs(result.rms - 0.005) < 0.001)
        for (index, name) in form.parameterNames.enumerated() {
            let error = try #require(result.standardErrors[index], "\(name)")
            #expect(abs(result.parameters[index] - Self.truth(form)[index]) <= 4 * error, "\(name)")
        }
    }

    @Test func straightLineMeetsZeroAtTheToe() throws {
        let curve = DigitizedCurve(name: "line", x: [-1, 0, 1, 2], y: [0.5, 1.0, 1.5, 2.0])
        let line = try #require(NegativeFit.straightLine(curve))
        #expect(abs(line.slope - 0.5) < 1e-12 && abs(line.intercept - 1.0) < 1e-12)
    }

    /// A fit whose green curve falls (toe far narrower than the shoulder) never reaches a stock file: the engine's
    /// validation rejects it, naming the layer.
    @Test func fitWithAFallingCurveIsRejected() throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let falling = (gamma: 0.55, toeExposure: 0.0, toeWidth: 0.02, shoulderExposure: 0.5, shoulderWidth: 2.0)
        let report = Self.syntheticReport(base: base.negative) { layer, parameters in
            guard layer == .green else { return parameters }
            return [0, falling.gamma, falling.toeExposure, falling.toeWidth, falling.shoulderExposure, falling.shoulderWidth]
        }
        #expect {
            try FittedStock.make(base: base, report: report, fitDate: nil)
        } throws: { error in
            guard case .fittedStockRejected(let reason) = error as? NegativeFitError else { return false }
            return reason.contains("green layer's negative curve")
        }
    }

    /// The bundled default's provenance sentence describes one datasheet; another stock's fit can't become it.
    @Test func bundledDefaultIsMadeFromItsSourceStockOnly() throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let other = try FittedStock.make(base: base, report: Self.syntheticReport(base: base.negative) { $1 }, fitDate: nil)
        #expect(throws: NegativeFitError.notTheDefaultSource("synthetic", expected: FittedStock.defaultSourceStock)) {
            try FittedStock.bundledDefault(from: other)
        }
    }

    /// A toe-and-shoulder report with `base`'s curves and printing density, each layer's parameters (in
    /// `NegativeCurveForm.toeShoulder.parameterNames` order) passed through `edit`. No traced samples.
    static func syntheticReport(
        base: FilmStock.Negative, edit: (NegativeFit.Layer, [Double]) -> [Double]
    ) -> NegativeFitReport {
        let none = NegativeFitReport.Statistics(sampleCount: 0, rms: 0, maxAbsResidual: 0, maxAbsLogExposure: 0, thirds: [])
        let layers = NegativeFit.Layer.allCases.enumerated().map { index, layer in
            let parameters = edit(
                layer,
                [
                    0, base.gamma[index], base.toeExposure[index], base.toeWidth[index], base.shoulderExposure[index],
                    base.shoulderWidth[index],
                ])
            return NegativeFitReport.LayerFit(
                layer: layer,
                parameters: zip(NegativeCurveForm.toeShoulder.parameterNames, parameters).map {
                    .init(name: $0, value: $1, standardError: nil)
                },
                optimizer: .init(
                    path: .levenbergMarquardt, termination: .costChange, converged: true, iterations: 1, nelderMeadEvaluations: 0,
                    parametersOnBounds: [], standardErrorNote: nil),
                dyeAmount: none, statusM: none, interpolatedSampleCount: 0, shoulderBeyondLastTracedStops: 0)
        }
        let residuals = PrintingDensityConversion.Residuals(sampleCount: 0, rms: [0, 0, 0], maxAbs: [0, 0, 0])
        return NegativeFitReport(
            tool: "test", stock: "synthetic",
            source: .init(publisher: "Test", document: "T-1", title: "Synthetic", revision: "1", url: "", pdfSHA256: ""),
            characteristicSHA256: "", spectralDyeDensitySHA256: "", standards: [], densitometry: "synthetic",
            midGrayLogExposure: 0, notes: [], digitizingUncertainty: .init(x: 0, y: 0, note: ""), bounds: [:],
            targetRMS: NegativeFitReport.targetRMS, targetStock: NegativeFitReport.targetStock, meetsTarget: nil, gammas: [],
            lastTracedStops: 0,
            printingDensity: PrintingDensityConversion(
                model: .dyeAmountsWithOffset, fittedOn: .neutralScaleAndLattice, neutralScaleWeight: 1,
                matrix: (0..<3).map { row in (0..<3).map { base.printingDensity[$0, row] } }, offset: [0, 0, 0], neutralScale: residuals,
                lattice: residuals),
            fits: [.init(form: .toeShoulder, layers: layers, samples: [])])
    }

    // MARK: Real data

    static let negatives = StockDataTests.stocks(.cameraNegative)
    /// The negative fit needs the local reference data and the standards tables (printing density).
    static let hasData = DyeSetDataTests.standardsAvailable
    static let standards: StandardsTables? = hasData ? (try? StandardsTables.load(from: DyeSetDataTests.standardsDirectory)) : nil

    /// Each camera negative fitted once from the local data, shared by the tests below.
    static let reports: [String: NegativeFitReport] = negatives.reduce(into: [:]) { reports, id in
        guard let standards else { return }
        reports[id] = try? NegativeFitReport.fitting(StockDataTests.load(id), standards: standards, tool: FitTool.toolName)
    }

    static func report(_ id: String) throws -> NegativeFitReport {
        try #require(reports[id], "\(id) didn't load or fit; run `emulsion-fit negative --stock \(id)` for the error")
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func realFitsConverge(_ id: String) throws {
        let report = try Self.report(id)
        #expect(report.fits.map(\.form) == NegativeCurveForm.allCases)
        for fit in report.fits {
            for layer in fit.layers { #expect(layer.optimizer.converged, "\(fit.form) \(layer.layer)") }
        }
        let toeShoulder = try #require(report.fit(.toeShoulder))
        for layer in toeShoulder.layers { #expect(layer.optimizer.parametersOnBounds.isEmpty, "\(layer.layer)") }
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func reportedRMSMatchesItsSampleTable(_ id: String) throws {
        for fit in try Self.report(id).fits {
            for layer in fit.layers {
                let own = fit.samples.filter { $0.layer == layer.layer }
                #expect(abs(own.map { $0.dyeAmount - $0.fittedDyeAmount }.rms - layer.dyeAmount.rms) <= 1e-12)
                #expect(abs(own.map { $0.statusM - $0.fittedStatusM }.rms - layer.statusM.rms) <= 1e-12)
            }
        }
    }

    /// MOV-25 acceptance: per layer, Status M RMS ≤ 0.03 D, and at least 4× below the logistic's.
    @Test(.enabled(if: hasData && negatives.contains(NegativeFitReport.targetStock)))
    func toeShoulderMeetsTheTargetAndBeatsTheLogistic() throws {
        let report = try Self.report(NegativeFitReport.targetStock)
        let toeShoulder = try #require(report.fit(.toeShoulder)).layers
        let logistic = try #require(report.fit(.logistic)).layers
        for (fitted, comparison) in zip(toeShoulder, logistic) {
            #expect(fitted.statusM.rms <= NegativeFitReport.targetRMS, "\(fitted.layer)")
            #expect(4 * fitted.statusM.rms <= comparison.statusM.rms, "\(fitted.layer)")
        }
        #expect(report.meetsTarget == true)
    }

    /// The RMS target is MOV-25's for one stock; others are compared with it, never judged by it.
    @Test(.enabled(if: hasData), arguments: negatives.filter { $0 != NegativeFitReport.targetStock })
    func otherStocksGetNoTargetVerdict(_ id: String) throws {
        let report = try Self.report(id)
        #expect(report.meetsTarget == nil)
        #expect(NegativeFitSummary.text(report).contains("target is set for \(NegativeFitReport.targetStock) only"))
    }

    @Test(.enabled(if: hasData), arguments: negatives)
    func fittedStockPassesTheEngine(_ id: String) throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let report = try Self.report(id)
        let stock = try FittedStock.make(base: base, report: report, fitDate: nil)
        let model = try FilmModel(stock: FilmStock(data: stock.encoded()))
        #expect(stock.provenance.fitDate == nil)
        #expect(stock.provenance.sourceSHA256 == (try StockDataTests.load(id)).characteristic.sha256)
        #expect(stock.rendering == base.rendering && stock.negative.sensitivity == base.negative.sensitivity)
        #expect(stock.print.dyes == base.print.dyes && stock.print.shape == base.print.shape)
        // Print contrast rebalanced so print gamma × printing-density gamma is the base's on every channel.
        let baseProduct = base.systemContrast[FittedStock.contrastAnchorChannel]
        for c in 0..<3 { #expect(abs(stock.systemContrast[c] - baseProduct) < 1e-12) }
        #expect(stock.provenance.sourceStock == id)
        #expect(model.printingDensity == simd_double3x3(rows: report.printingDensity.matrix.map { SIMD3($0) }))
    }

    /// `emulsion-fit negative --stock <defaultSourceStock> --out <dir> --fit-date <its fitDate> --bundled-default <file>`,
    /// starting from the bundled default itself, writes the bundled default and the committed fit again: regenerating
    /// changes nothing. Numbers are compared within 1e-9, not as bytes: debug and release builds differ in the last digits
    /// (measured up to 4e-12) because the optimizer reorders floating-point arithmetic.
    @Test(.enabled(if: hasData && negatives.contains(FittedStock.defaultSourceStock)))
    func bundledDefaultAndCommittedFitAreWhatTheToolRegenerates() throws {
        let id = FittedStock.defaultSourceStock
        let bundled = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let out = FileManager.default.temporaryDirectory.appending(path: "emulsion-fit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let defaultFile = out.appending(path: "emulsion-default.json")
        _ = try FitTool.perform(
            .negative(
                .init(
                    shared: .init(stock: id, out: out, standards: DyeSetDataTests.standardsDirectory), fitDate: bundled.provenance.fitDate,
                    bundledDefault: defaultFile)))
        let pairs = [
            (try Data(contentsOf: defaultFile), try FilmStock.bundledFile(named: FitTool.defaultBaseStock)),
            (try Data(contentsOf: out.appending(path: "\(id).stock.json")), try Self.committedStock(id)),
        ]
        for (regenerated, shipped) in pairs {
            let differences = try Self.differences(
                JSONSerialization.jsonObject(with: regenerated), JSONSerialization.jsonObject(with: shipped))
            #expect(differences.isEmpty, "\(differences)")
        }
    }

    /// Paths where two decoded JSON trees differ: numbers by more than 1e-9, anything else at all.
    static func differences(_ a: Any, _ b: Any, path: String = "") -> [String] {
        switch (a, b) {
        case (let a as [String: Any], let b as [String: Any]):
            guard Set(a.keys) == Set(b.keys) else { return ["\(path): keys \(a.keys.sorted()) vs \(b.keys.sorted())"] }
            return a.keys.sorted().flatMap { key in differences(a[key] ?? NSNull(), b[key] ?? NSNull(), path: "\(path).\(key)") }
        case (let a as [Any], let b as [Any]):
            guard a.count == b.count else { return ["\(path): \(a.count) vs \(b.count) elements"] }
            return zip(a, b).enumerated().flatMap { differences($1.0, $1.1, path: "\(path)[\($0)]") }
        case (let a as String, let b as String):
            return a == b ? [] : ["\(path): \(a) vs \(b)"]
        case (let a as NSNumber, let b as NSNumber):
            return abs(a.doubleValue - b.doubleValue) <= 1e-9 ? [] : ["\(path): \(a) vs \(b)"]
        default:
            return ["\(path): \(a) vs \(b)"]
        }
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
        _ = try FitTool.perform(
            .negative(.init(shared: .init(stock: id, out: out, standards: DyeSetDataTests.standardsDirectory), name: "Warm test")))
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
        let standards = try #require(Self.standards)
        #expect(throws: NegativeFitError.notACameraNegative(id)) {
            try NegativeFitReport.fitting(StockDataTests.load(id), standards: standards, tool: FitTool.toolName)
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
        #expect(stock.provenance.sourceStock == id)
        #expect(stock.provenance.fitResiduals?.isEmpty == false)
        let name = stock.name.lowercased()
        for word in ["kodak", "vision", "5207", "5219"] { #expect(!name.contains(word), "\(stock.name)") }
    }

    /// Words that must not appear in a file the apps ship (MOV-92), compared case-insensitively.
    static let brandWords = ["kodak", "vision3", "eastman", "fuji"]

    /// The shipped default is the committed fit of `FittedStock.defaultSourceStock` with a brand-free name and provenance
    /// (MOV-92): the same numbers and tracing digest, so the two copies can't drift apart unnoticed.
    @Test func bundledDefaultIsTheCommittedFitWithoutBrandNames() throws {
        let file = try FilmStock.bundledFile(named: FitTool.defaultBaseStock)
        let bundled = try FilmStock(data: file)
        let committed = try FilmStock(data: Self.committedStock(FittedStock.defaultSourceStock))
        #expect(bundled.negative == committed.negative)
        #expect(bundled.print == committed.print)
        #expect(bundled.rendering == committed.rendering)
        #expect(bundled.provenance.sourceSHA256 == committed.provenance.sourceSHA256)
        let text = try #require(String(data: file, encoding: .utf8)).lowercased()
        for word in Self.brandWords { #expect(!text.contains(word), "\(word)") }
    }

    @Test(arguments: StockDataTests.stocks(.printFilm))
    func printFilmHasNoFittedStock(_ id: String) throws {
        let directory = try #require(StockDataTests.manifestsDirectory)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "\(id)/\(FittedStock.committedFileName)").path))
    }

    /// The committed file is what `emulsion-fit negative --fit-date 2026-11-12` writes from the pinned tracing, within
    /// the build-to-build tolerance of `bundledDefaultAndCommittedFitAreWhatTheToolRegenerates`.
    @Test(.enabled(if: hasData), arguments: negatives)
    func refittingReproducesTheCommittedStock(_ id: String) throws {
        let base = try FilmStock.bundled(named: FitTool.defaultBaseStock)
        let stock = try FittedStock.make(base: base, report: Self.report(id), fitDate: "2026-11-12")
        let differences = try Self.differences(
            JSONSerialization.jsonObject(with: stock.encoded()), JSONSerialization.jsonObject(with: Self.committedStock(id)))
        #expect(differences.isEmpty, "\(differences)")
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
