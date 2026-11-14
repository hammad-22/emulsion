import Foundation

/// The readable tables `emulsion-fit negative` prints; the JSON report holds the same numbers in full.
enum NegativeFitSummary {
    static func text(_ report: NegativeFitReport) -> String {
        let uncertainty = report.digitizingUncertainty
        var lines = [
            "\(report.stock): \(report.source.document), \(report.source.revision)",
            "Conditions: \(report.densitometry)",
            "Mid-gray at log10 exposure \(report.midGrayLogExposure) (approximate anchor; shifts exposures only)",
            String(format: "Digitizing 1σ per point: x %.4f log10, y %.4f D", uncertainty.x, uncertainty.y),
            "Fitted to the neutral scale's dye amounts (from the digitized dye set through Status M); x relative to mid-gray.",
            "Residuals: measured − fitted, in dye amount and in the chart's Status M. ± values are fit-statistics standard "
                + "errors, excluding digitizing error.",
            "",
            "Straight-line gammas (middle third of each span):",
        ]
        lines += report.gammas.map { row in
            "  " + row.quantity.padding(toLength: 22, withPad: " ", startingAt: 0)
                + row.values.map { $0.map { String(format: "%.3f", $0) } ?? "—" }.joined(separator: " / ")
        }
        lines.append(
            String(
                format: "Last traced sample: %+.2f stops above mid-gray; the curve beyond it (the flat top) is extrapolated.",
                report.lastTracedStops))
        for fit in report.fits {
            lines += ["", "\(fit.form.rawValue): " + fit.form.parameterNames.joined(separator: ", ")]
            for layer in fit.layers {
                let optimizer = layer.optimizer
                lines.append(
                    "  \(layer.layer.rawValue): " + layer.parameters.map(estimate).joined(separator: "  ")
                        + "  [\(optimizer.termination.rawValue), \(optimizer.iterations) it"
                        + (optimizer.parametersOnBounds.isEmpty
                            ? "" : "; on a bound: \(optimizer.parametersOnBounds.joined(separator: ", "))")
                        + "]")
                if let beyond = layer.shoulderBeyondLastTracedStops {
                    lines.append(
                        beyond > 0
                            ? String(format: "         shoulder exposure %.2f stops beyond the last traced sample (extrapolated)", beyond)
                            : String(
                                format: "         shoulder exposure %.2f stops below the last traced sample (inside the traced range)",
                                -beyond))
                }
            }
            lines.append("  layer  residual   RMS     max|r|  @logE   toe/mid/shoulder mean r")
            for layer in fit.layers {
                for (name, stats) in [("dye amt ", layer.dyeAmount), ("Status M", layer.statusM)] {
                    let thirds = stats.thirds.map { String(format: "%+.4f", $0.meanResidual) }.joined(separator: " ")
                    lines.append(
                        "  " + layer.layer.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0) + name
                            + String(format: "   %.4f  %.4f  %+.2f   ", stats.rms, stats.maxAbsResidual, stats.maxAbsLogExposure) + thirds)
                }
            }
        }
        let verdict =
            report.meetsTarget.map { $0 ? "met" : "missed" }
            ?? "the target is set for \(report.targetStock) only"
        lines += [
            "",
            String(format: "MOV-25 acceptance, toeShoulder Status M RMS ≤ %.2f D per layer: ", report.targetRMS) + verdict,
        ]
        let conversion = report.printingDensity
        lines += [
            "",
            "Printing-density matrix written to the stock: \(conversion.formula), APD, neutral scale weighted "
                + String(format: "%.0f", conversion.neutralScaleWeight) + " (offset not stored: the printer lights absorb it).",
            "  rows APD R, G, B; columns cyan, magenta, yellow; offset b",
        ]
        for (row, offset) in zip(conversion.matrix, conversion.offset ?? [0, 0, 0]) {
            lines.append("  " + (row + [offset]).map { String(format: "%+.4f", $0) }.joined(separator: "  "))
        }
        lines.append(
            "  neutral scale max |r| " + conversion.neutralScale.maxAbs.map { String(format: "%.4f", $0) }.joined(separator: " / ")
                + "; lattice RMS " + conversion.lattice.rms.map { String(format: "%.4f", $0) }.joined(separator: " / ")
                + ", max " + conversion.lattice.maxAbs.map { String(format: "%.4f", $0) }.joined(separator: " / ") + " D")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func estimate(_ parameter: NegativeFitReport.Parameter) -> String {
        String(format: "%.4f", parameter.value) + (parameter.standardError.map { String(format: "±%.4f", $0) } ?? "±—")
    }
}
