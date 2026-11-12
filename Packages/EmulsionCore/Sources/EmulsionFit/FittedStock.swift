import EmulsionCore

/// The stock file a negative fit writes: a base stock with its negative characteristic curves (gamma, density range,
/// exposure offset) replaced by the shared-range fit, and provenance saying exactly what was and wasn't fitted.
enum FittedStock {
    /// The name a fitted stock file is committed under, next to its manifest in `StockData/<id>/`. Only parameters and
    /// provenance; the report and plot table hold traced samples and stay local.
    static let committedFileName = "negative-fit.stock.json"

    /// - Parameter name: the stock's display name. It defaults to the base name and never carries the datasheet's
    ///   stock id or publisher, which stay in provenance: product UI may show the name (MOV-92).
    static func make(base: FilmStock, report: NegativeFitReport, fitDate: String?, name: String? = nil) throws(NegativeFitError)
        -> FilmStock
    {
        guard let fit = report.fit(.sharedRange), fit.layers.count == 3 else {
            throw .fittedStockRejected("the report has no shared-range fit.")
        }
        var stock = base
        stock.name = name ?? "\(base.name), fitted negative"
        stock.negative.gamma = SIMD3(fit.layers.map(\.gamma.value))
        stock.negative.densityRange = fit.layers[0].densityRange.value
        stock.negative.exposureOffset = SIMD3(fit.layers.map(\.exposureOffset.value))

        var residuals = ["rmsDensity": fit.overall.rms, "maxAbsDensity": fit.overall.maxAbsResidual]
        for layer in fit.layers {
            residuals["\(layer.layer.rawValue).rmsDensity"] = layer.statistics.rms
            residuals["\(layer.layer.rawValue).maxAbsDensity"] = layer.statistics.maxAbsResidual
        }
        let source = report.source
        let minimumDensities = fit.layers.map { "\($0.layer.rawValue) \(String(format: "%.3f", $0.minimumDensity.value))" }
        stock.provenance = FilmStock.Provenance(
            source: "\(source.publisher) \(source.document), \"\(source.title)\", \(source.revision). \(source.url)",
            fitDate: fitDate, tool: report.tool, sourceSHA256: report.characteristicSHA256, fitResiduals: residuals,
            notes: [
                "Chart conditions: \(report.densitometry).",
                "Only the negative characteristic curves (gamma, densityRange, exposureOffset) were fitted, to the digitized "
                    + "characteristic chart; every other parameter is the hand-tuned value of \"\(base.name)\".",
                "Minimum densities (base + fog + mask) were fitted (\(minimumDensities.joined(separator: ", "))) but are not "
                    + "stored: the engine's calibrated printer lights absorb a constant per-layer density.",
                "Exposure offsets are relative to mid-gray at log10 exposure \(report.midGrayLogExposure) lux-seconds on the chart, "
                    + "an approximate anchor (see the fit report).",
                "fitResiduals are measured − fitted density over the traced samples; they exclude the digitizing error.",
            ] + fit.notes)
        do {
            _ = try FilmModel(stock: stock)
        } catch {
            throw .fittedStockRejected(error.developerDescription)
        }
        return stock
    }
}
