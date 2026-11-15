extension NegativeDyeSetReport {
    struct ConversionSet: Codable, Sendable, Equatable {
        let printingDensity: String
        let fits: [PrintingDensityConversion]

        /// Each model on both sets, the engine form at each weight, Status M on the neutral scale.
        static func fitting(
            printingDensity: String, neutralScale: [PrintingDensityConversion.Point], lattice: [PrintingDensityConversion.Point]
        ) throws(DyeSetError) -> ConversionSet {
            var fits: [PrintingDensityConversion] = []
            for model in PrintingDensityConversion.Model.allCases {
                fits.append(try PrintingDensityConversion.fit(model, neutralScale: neutralScale, lattice: lattice))
            }
            for weight in PrintingDensityConversion.neutralScaleWeightSweep where weight != 1 {
                fits.append(
                    try PrintingDensityConversion.fit(
                        .dyeAmountsWithOffset, neutralScaleWeight: weight, neutralScale: neutralScale, lattice: lattice))
            }
            for model in [PrintingDensityConversion.Model.statusM, .statusMWithOffset] {
                fits.append(try PrintingDensityConversion.fit(model, on: .neutralScale, neutralScale: neutralScale, lattice: lattice))
            }
            return ConversionSet(printingDensity: printingDensity, fits: fits)
        }

        func fit(
            _ model: PrintingDensityConversion.Model, fittedOn fitSet: PrintingDensityConversion.FitSet = .neutralScaleAndLattice,
            neutralScaleWeight: Double = 1
        ) -> PrintingDensityConversion? {
            fits.first { $0.model == model && $0.fittedOn == fitSet && $0.neutralScaleWeight == neutralScaleWeight }
        }

        var engine: PrintingDensityConversion? {
            fit(.dyeAmountsWithOffset, neutralScaleWeight: PrintingDensityConversion.engineNeutralScaleWeight)
        }
    }
}
