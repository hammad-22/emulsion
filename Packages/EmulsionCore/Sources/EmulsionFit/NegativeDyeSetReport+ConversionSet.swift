extension NegativeDyeSetReport {
    struct ConversionSet: Codable, Sendable, Equatable {
        let printingDensity: String
        let fits: [PrintingDensityConversion]

        /// Every fit the report compares: each model on the neutral scale and lattice, the engine form at each
        /// `neutralScaleWeightSweep` weight, and the Status M fits on the neutral scale alone.
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

        /// The conversion the engine uses.
        var engine: PrintingDensityConversion? {
            fit(.dyeAmountsWithOffset, neutralScaleWeight: PrintingDensityConversion.engineNeutralScaleWeight)
        }
    }
}
