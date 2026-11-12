import Foundation

/// The Markdown summary `emulsion-fit dyes` writes and prints; the JSON report holds the same numbers in full.
enum NegativeDyeSetSummary {
    static func text(_ report: NegativeDyeSetReport) -> String {
        let midscale = report.midscale
        var lines = [
            "# \(report.stock): dye set and printing density",
            "",
            "Source: \(report.source.document), \(report.source.revision). Computed by \(report.tool) from the digitized datasheet "
                + "spectra and curves through the standards' responsivities; no number here is a measurement of film.",
            "",
            "## Midscale reconstruction (MOV-88)",
            "",
            "Least-squares dye amounts so that Dmin + Σ a·dye matches the midscale neutral, "
                + String(format: "%.0f–%.0f nm", midscale.wavelengths.first ?? .nan, midscale.wavelengths.last ?? .nan)
                + " in 10 nm steps (\(midscale.wavelengths.count) wavelengths).",
            "",
            "| cyan | magenta | yellow | RMS (D) | max \\|r\\| (D) | at nm | target ≤ \(format(midscale.targetMaxResidual, 2)) |",
            "| ---: | ---: | ---: | ---: | ---: | ---: | --- |",
            "| " + (midscale.amounts + [midscale.rms, midscale.maxAbsResidual]).map { format($0) }.joined(separator: " | ")
                + " | \(format(midscale.wavelengthOfMax, 0)) | \(midscale.meetsTarget ? "met" : "missed") |",
            "",
            "## Minimum density (base + fog + mask)",
            "",
            "Integral density of the minimum-density spectrum against the characteristic chart's lowest traced density "
                + "(the chart is Status M, so only that row compares like with like).",
            "",
            "| Density | R | G | B | chart lowest R | G | B | difference R | G | B |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        lines += report.mask.map { row in
            "| \(row.densityDefinition) | " + (row.minimumDensity + row.chartLowest).map { format($0) }.joined(separator: " | ") + " | "
                + row.difference.map { format($0, signed: true) }.joined(separator: " | ") + " |"
        }
        lines += [
            "",
            "## Neutral-scale straight-line gammas",
            "",
            "Least-squares slope over the middle third of each curve's span, per log10 lux-second.",
            "",
            "| Quantity | R / cyan | G / magenta | B / yellow |",
            "| --- | ---: | ---: | ---: |",
        ]
        lines += report.gammas.map { row in
            "| \(row.quantity) | " + row.values.map { $0.map { format($0) } ?? "—" }.joined(separator: " | ") + " |"
        }
        lines += [
            "",
            "## Printing-density conversions",
            "",
            "Linear least squares on \(report.neutralScale.count) neutral-scale samples plus a \(report.latticeSteps)³ lattice of dye "
                + "amounts (0 to " + report.latticeMaxAmounts.map { format($0) }.joined(separator: " / ")
                + " cyan / magenta / yellow). Residual = printing density − fitted, in D. The Status M fits are repeated on the neutral scale alone.",
        ]
        for set in report.conversions {
            lines += ["", "### \(set.printingDensity)", ""]
            for fit in set.fits {
                let isDyes = fit.model == .dyeAmounts || fit.model == .dyeAmountsWithOffset
                lines.append(
                    "\(label(fit)):" + (isDyes ? " (rows R, G, B; columns cyan, magenta, yellow)" : " (columns Status M R, G, B)")
                        + (fit == set.engine ? " — the engine's matrix" : ""))
                lines.append("")
                lines.append(fit.offset == nil ? "| | | |" : "| | | | b |")
                lines.append(fit.offset == nil ? "| ---: | ---: | ---: |" : "| ---: | ---: | ---: | ---: |")
                for (index, row) in fit.matrix.enumerated() {
                    let offset = fit.offset.map { [format($0[index], signed: true)] } ?? []
                    lines.append("| " + (row.map { format($0, signed: true) } + offset).joined(separator: " | ") + " |")
                }
                lines.append("")
            }
            lines += [
                "Engine matrix (PD = P·c + b) by neutral-scale weight w, unweighted residuals in D:",
                "",
            ]
            lines += comparisonTable(
                "w",
                PrintingDensityConversion.neutralScaleWeightSweep.compactMap { weight in
                    set.fit(.dyeAmountsWithOffset, neutralScaleWeight: weight).map { (format(weight, 0), $0) }
                })
            lines += ["", "Status M → printing density, 3×3 against 3×3 + offset:", ""]
            lines += comparisonTable(
                "Fit",
                [PrintingDensityConversion.FitSet.neutralScaleAndLattice, .neutralScale].flatMap { fitSet in
                    [PrintingDensityConversion.Model.statusM, .statusMWithOffset].compactMap { model in
                        set.fit(model, fittedOn: fitSet).map { (label($0), $0) }
                    }
                })
            lines += [
                "",
                "All fits:",
                "",
                "| Fit | residuals on | samples | RMS R | RMS G | RMS B | max \\|r\\| R | max \\|r\\| G | max \\|r\\| B |",
                "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            ]
            for scope in ["neutral scale", "lattice"] {
                for fit in set.fits {
                    let residuals = scope == "lattice" ? fit.lattice : fit.neutralScale
                    lines.append(
                        "| \(label(fit)) | \(scope) | \(residuals.sampleCount) | "
                            + (residuals.rms + residuals.maxAbs).map { format($0, 4) }.joined(separator: " | ") + " |")
                }
            }
        }
        let edge = report.dyeEdgeDiagnostic
        lines += [
            "",
            "## Hold-end assumption",
            "",
            "Zero-filling the dye curves outside their traced spans instead of holding their end values changes the neutral scale's "
                + "dye amounts by at most \(format(edge.dyeAmounts, 4)), its APD by \(format(edge.academyPrintingDensity)) D, its RP 180 "
                + "density by \(format(edge.rp180PrintingDensity)) D, and the engine's APD matrix by \(format(edge.academyDyeMatrix)).",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func label(_ fit: PrintingDensityConversion) -> String {
        let weight = fit.neutralScaleWeight == 1 ? "" : ", neutral scale weighted \(format(fit.neutralScaleWeight, 0))"
        return fit.formula
            + (fit.fittedOn == .neutralScale ? " (fitted on neutral scale)" : " (fitted on neutral scale + lattice\(weight))")
    }

    /// Neutral-scale max, lattice RMS and lattice max per channel, one row per fit.
    private static func comparisonTable(_ title: String, _ rows: [(String, PrintingDensityConversion)]) -> [String] {
        [
            "| \(title) | neutral max R | G | B | lattice RMS R | G | B | lattice max R | G | B |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
            + rows.map { name, fit in
                "| \(name) | "
                    + (fit.neutralScale.maxAbs + fit.lattice.rms + fit.lattice.maxAbs).map { format($0, 4) }.joined(separator: " | ")
                    + " |"
            }
    }

    private static func format(_ value: Double, _ digits: Int = 3, signed: Bool = false) -> String {
        String(format: signed ? "%+.\(digits)f" : "%.\(digits)f", value)
    }
}
