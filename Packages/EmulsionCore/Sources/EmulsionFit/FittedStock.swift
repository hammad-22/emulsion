import EmulsionCore
import Foundation
import simd

/// The stock file a negative fit writes: a base stock with its negative replaced by the toe-and-shoulder fit and the
/// APD printing-density matrix, its print gammas rebalanced per channel, and provenance saying exactly what was and
/// wasn't fitted.
enum FittedStock {
    /// The name a fitted stock file is committed under, next to its manifest in `StockData/<id>/`. Only parameters and
    /// provenance; the report and plot table hold traced samples and stay local.
    static let committedFileName = "negative-fit.stock.json"
    /// The channel whose system contrast the fitted stock keeps: green carries most of the luminance, and it is the
    /// channel the previous default's product was read from.
    static let contrastAnchorChannel = 1
    /// The datasheet stock the bundled default (`FitTool.defaultBaseStock`) is fitted to.
    static let defaultSourceStock = "kodak-vision3-250d-5207"
    static let bundledDefaultName = "Emulsion Default"
    /// The bundled default's `source`. The apps ship that file, so it names no film brand (MOV-92); `sourceSHA256` leads
    /// to the committed fit of the same tracing, which keeps the datasheet's full provenance.
    static let bundledDefaultSource =
        "Negative fitted to a published camera-negative datasheet (daylight-balanced, ECN-2). The datasheet, revision and "
        + "checksums are recorded with the fit in the engine repository: Packages/EmulsionCore/Sources/EmulsionFit/Resources/"
        + "StockData/, file \(committedFileName) of the stock whose sourceSHA256 matches."

    /// - Parameter name: the stock's display name. It defaults to the base name and never carries the datasheet's
    ///   stock id or publisher, which stay in provenance: product UI may show the name (MOV-92).
    static func make(base: FilmStock, report: NegativeFitReport, fitDate: String?, name: String? = nil) throws(NegativeFitError)
        -> FilmStock
    {
        guard let fit = report.fit(.toeShoulder), fit.layers.count == 3 else {
            throw .fittedStockRejected("the report has no toe-and-shoulder fit.")
        }
        func parameter(_ name: String) -> SIMD3<Double> { SIMD3(fit.layers.map { $0.value(name) ?? .nan }) }
        let conversion = report.printingDensity
        var stock = base
        stock.name = name ?? "\(base.name), fitted negative"
        stock.negative.gamma = parameter("gamma")
        stock.negative.toeExposure = parameter("toeExposure")
        stock.negative.toeWidth = parameter("toeWidth")
        stock.negative.shoulderExposure = parameter("shoulderExposure")
        stock.negative.shoulderWidth = parameter("shoulderWidth")
        stock.negative.printingDensity = simd_double3x3(rows: conversion.matrix.map { SIMD3($0) })
        let systemContrast = base.systemContrast[contrastAnchorChannel]
        stock.rebalancePrintGamma(systemContrast: systemContrast)

        var residuals: [String: Double] = [:]
        for layer in fit.layers {
            residuals["\(layer.layer.rawValue).statusM.rms"] = layer.statusM.rms
            residuals["\(layer.layer.rawValue).statusM.maxAbs"] = layer.statusM.maxAbsResidual
            residuals["\(layer.layer.rawValue).dyeAmount.rms"] = layer.dyeAmount.rms
        }
        for (index, channel) in NegativeFit.Layer.allCases.enumerated() {
            residuals["printingDensity.\(channel.rawValue).neutralScale.maxAbs"] = conversion.neutralScale.maxAbs[index]
            residuals["printingDensity.\(channel.rawValue).lattice.rms"] = conversion.lattice.rms[index]
        }
        let source = report.source
        let offsets = (conversion.offset ?? []).map { String(format: "%+.4f", $0) }.joined(separator: ", ")
        stock.provenance = FilmStock.Provenance(
            source: "\(source.publisher) \(source.document), \"\(source.title)\", \(source.revision). \(source.url)",
            fitDate: fitDate, tool: report.tool, sourceStock: report.stock, sourceSHA256: report.characteristicSHA256,
            fitResiduals: residuals,
            notes: [
                "Chart conditions: \(report.densitometry).",
                "Fitted: the negative curves (gamma, toeExposure, toeWidth, shoulderExposure, shoulderWidth, per layer) to the "
                    + "neutral scale's dye amounts, computed from the digitized characteristic and spectral dye density charts "
                    + "(sha256 \(report.characteristicSHA256), \(report.spectralDyeDensitySHA256)) through ISO 5-3 Status M; "
                    + "and printingDensity, \(conversion.formula) through SMPTE ST 2065-2 APD, fitted on the neutral scale "
                    + "(weighted \(String(format: "%.0f", conversion.neutralScaleWeight))) and a lattice of dye amounts.",
                "Not stored: the fitted per-layer dye-amount offsets and the printing-density offset b (\(offsets)); the "
                    + "calibrated printer lights absorb a constant per-layer density.",
                "shoulderExposure lies "
                    + fit.layers.map { String(format: "%+.2f", $0.shoulderBeyondLastTracedStops ?? .nan) }.joined(separator: ", ")
                    + " stops from the last traced sample (at " + String(format: "%+.2f", report.lastTracedStops)
                    + " stops; negative = inside the traced range). The curve beyond the last traced sample, its flat top, "
                    + "is extrapolated.",
                "Exposures are relative to mid-gray at log10 exposure \(report.midGrayLogExposure) lux-seconds on the chart, an "
                    + "approximate anchor (see the fit report).",
                "Print gamma rebalanced per channel to "
                    + String(format: "%.4f", systemContrast)
                    + " / (printingDensity · gamma): a print stock's layer contrasts are matched to the printing-density "
                    + "contrasts of the negatives it prints (SMPTE RP 180-1999 Introduction); without it the gray scale "
                    + "turns green/magenta away from mid-gray. The overall level, the product of print and negative "
                    + "contrast, is carried over from \"\(base.name)\" and is artistic (MOV-5).",
                "Hand-tuned, from \"\(base.name)\": sensitivity, the print's minimum density, density range, shape and dyes, "
                    + "and the rendering choices.",
                "fitResiduals: measured − fitted Status M density and dye amount per layer over the traced samples, and the "
                    + "printing-density matrix's residuals; they exclude the digitizing error.",
            ])
        do {
            _ = try FilmModel(stock: stock)
        } catch {
            throw .fittedStockRejected(error.developerDescription)
        }
        return stock
    }

    /// The engine's bundled default (`Resources/Stocks/emulsion-default.json`) made from `fitted`, the fit of
    /// `defaultSourceStock`: the same parameters, named `bundledDefaultName`, with the datasheet's publisher, title, URL and
    /// stock id left out of its provenance (`bundledDefaultSource`). Date, tool, digest, residuals and notes are kept.
    static func bundledDefault(from fitted: FilmStock) throws(NegativeFitError) -> FilmStock {
        guard fitted.provenance.sourceStock == defaultSourceStock else {
            throw .notTheDefaultSource(fitted.provenance.sourceStock ?? "a stock with no sourceStock", expected: defaultSourceStock)
        }
        var stock = fitted
        stock.name = bundledDefaultName
        stock.provenance.source = bundledDefaultSource
        stock.provenance.sourceStock = nil
        return stock
    }
}
