extension NegativeDyeSetReport {
    /// The neutral scale's straight-line gammas (`NegativeFit.straightLineGamma`), red/cyan, green/magenta, blue/yellow.
    struct Gammas: Sendable, Equatable {
        enum Quantity: CaseIterable, Sendable {
            case statusM, dyeAmounts, academyPrintingDensity, rp180PrintingDensity, academyADX

            var label: String {
                switch self {
                case .statusM: "Status M"
                case .dyeAmounts: "Dye amounts (C, M, Y)"
                case .academyPrintingDensity: "APD"
                case .rp180PrintingDensity: "RP 180 PD"
                case .academyADX: "APD × ADX k (1.00, 0.92, 0.95)"
                }
            }
        }

        let statusM: [Double?]
        let dyeAmounts: [Double?]
        let academyPrintingDensity: [Double?]
        let rp180PrintingDensity: [Double?]

        init(_ scale: NeutralScale) {
            func gammas(_ quantity: Quantity, _ value: @escaping (NeutralScale.Sample) -> [Double]) -> [Double?] {
                (0..<3).map { NegativeFit.straightLineGamma(scale.curve(quantity.label, channel: $0, value)) }
            }
            statusM = gammas(.statusM, \.statusM)
            dyeAmounts = gammas(.dyeAmounts, \.dyeAmounts)
            academyPrintingDensity = gammas(.academyPrintingDensity, \.academyPrintingDensity)
            rp180PrintingDensity = gammas(.rp180PrintingDensity, \.rp180PrintingDensity)
        }

        func values(_ quantity: Quantity) -> [Double?] {
            switch quantity {
            case .statusM: statusM
            case .dyeAmounts: dyeAmounts
            case .academyPrintingDensity: academyPrintingDensity
            case .rp180PrintingDensity: rp180PrintingDensity
            case .academyADX: zip(academyPrintingDensity, adxChannelFactors).map { gamma, k in gamma.map { $0 * k } }
            }
        }

        func rows(_ quantities: [Quantity] = Quantity.allCases) -> [GammaRow] {
            quantities.map { GammaRow(quantity: $0.label, values: values($0)) }
        }
    }
}
