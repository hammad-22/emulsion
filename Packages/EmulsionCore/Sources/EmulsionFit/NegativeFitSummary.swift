import Foundation

/// The readable table `emulsion-fit negative` prints; the JSON report holds the same numbers in full.
enum NegativeFitSummary {
    static func text(_ report: NegativeFitReport) -> String {
        let uncertainty = report.digitizingUncertainty
        var lines = [
            "\(report.stock): \(report.source.document), \(report.source.revision)",
            "Conditions: \(report.densitometry)",
            "Mid-gray at log10 exposure \(report.midGrayLogExposure) (approximate anchor; shifts offsets only)",
            String(format: "Digitizing 1σ per point: x %.4f log10, y %.4f D", uncertainty.x, uncertainty.y),
            "Residual = measured − fitted density. ± values are fit-statistics standard errors, excluding digitizing error.",
        ]
        for fit in report.fits {
            let optimizer = fit.optimizer
            lines += [
                "",
                "\(fit.parameterization.rawValue) (\(fit.parameterCount) parameters): \(optimizer.termination.rawValue) "
                    + "after \(optimizer.iterations) iterations via \(optimizer.path.rawValue)"
                    + (optimizer.parametersOnBounds.isEmpty ? "" : "; on a bound: \(optimizer.parametersOnBounds.joined(separator: ", "))"),
                "layer  Dmin            gamma           straight  range           offset          RMS     max|r| @logE    "
                    + "toe/mid/shoulder mean r",
            ]
            for layer in fit.layers {
                let stats = layer.statistics
                let thirds = layer.exposureThirds.map { String(format: "%+.4f", $0.meanResidual) }.joined(separator: " ")
                lines.append(
                    layer.layer.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
                        + [layer.minimumDensity, layer.gamma].map(estimate).joined(separator: " ")
                        + (layer.straightLineGamma.map { String(format: " %6.4f   ", $0) } ?? "  —       ")
                        + [layer.densityRange, layer.exposureOffset].map(estimate).joined(separator: " ")
                        + String(format: " %.4f  %.4f %+.2f  ", stats.rms, stats.maxAbsResidual, stats.maxAbsLogExposure) + thirds)
            }
            lines += fit.notes.map { "Note: \($0)" }
            let overall = fit.overall
            lines.append(
                String(format: "all    RMS %.4f, max|r| %.4f (", overall.rms, overall.maxAbsResidual) + overall.maxAbsLayer.rawValue
                    + String(format: " at %+.2f), %d samples", overall.maxAbsLogExposure, overall.sampleCount))
            let interpolated = fit.layers.map(\.interpolatedSampleCount)
            if interpolated.contains(where: { $0 > 0 }) {
                lines.append(
                    "Interpolated or shared-line samples (fitted with full weight): "
                        + zip(fit.layers, interpolated).map { "\($0.layer.rawValue) \($1)" }.joined(separator: ", "))
            }
            if fit.parameterization == .sharedRange {
                let comparison = String(format: "Shared-range RMS %.4f D ", overall.rms)
                if let met = report.sharedRangeMeetsTarget {
                    lines.append(
                        comparison + String(format: "vs the %.2f D target for this stock: ", report.targetRMS) + (met ? "met" : "missed"))
                } else {
                    lines.append(comparison + String(format: "(the %.2f D target is set for \(report.targetStock) only)", report.targetRMS))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func estimate(_ estimate: NegativeFitReport.Estimate) -> String {
        let error = estimate.standardError.map { String(format: "±%.4f", $0) } ?? "±—    "
        return String(format: "%7.4f", estimate.value) + error + " "
    }
}
