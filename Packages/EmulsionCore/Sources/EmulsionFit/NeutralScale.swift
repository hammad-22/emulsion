/// The negative's neutral scale read through its dye set. At every characteristic-chart sample the Status M density
/// above each channel's lowest traced density fixes three dye amounts (Newton, from the previous sample's amounts);
/// those amounts then give the printing densities above minimum density.
struct NeutralScale: Sendable, Equatable {
    struct Sample: Codable, Sendable, Equatable {
        /// log10 lux-seconds, the characteristic chart's x.
        let logExposure: Double
        /// Red, green, blue: chart density minus that channel's lowest traced density.
        let statusM: [Double]
        /// Cyan, magenta, yellow.
        let dyeAmounts: [Double]
        let academyPrintingDensity: [Double]
        let rp180PrintingDensity: [Double]
    }

    let samples: [Sample]

    /// - Parameters:
    ///   - logExposure: ascending samples where every channel is traced.
    ///   - densities: red, green and blue Status M densities at those samples.
    static func solve(logExposure: [Double], densities: [[Double]], dyeSet: NegativeDyeSet, standards: StandardsTables)
        throws(DyeSetError) -> NeutralScale
    {
        let lowest = densities.map { $0.min() ?? 0 }
        let statusM = dyeSet.densitometer(standards.statusM)
        let academy = dyeSet.densitometer(standards.academyPrintingDensity)
        let rp180 = dyeSet.densitometer(standards.rp180)
        var amounts = [Double](repeating: 0, count: NegativeDyeSet.Dye.allCases.count)
        var samples: [Sample] = []
        for (i, x) in logExposure.enumerated() {
            let target = zip(densities, lowest).map { $0[i] - $1 }
            amounts = try statusM.amounts(forDensityAboveMinimum: target, from: amounts)
            samples.append(
                Sample(
                    logExposure: x, statusM: target, dyeAmounts: amounts,
                    academyPrintingDensity: academy.densityAboveMinimum(amounts),
                    rp180PrintingDensity: rp180.densityAboveMinimum(amounts)))
        }
        return NeutralScale(samples: samples)
    }

    /// One channel (or dye) of one quantity along the scale, as a curve for `NegativeFit.straightLineGamma`.
    func curve(_ name: String, channel: Int, _ value: (Sample) -> [Double]) -> DigitizedCurve {
        DigitizedCurve(name: name, x: samples.map(\.logExposure), y: samples.map { value($0)[channel] })
    }
}
