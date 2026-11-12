/// Checks on digitized data beyond what loading enforces: samples on the digitizer's grid, inside the traced
/// extent, and characteristic curves that never fall. Each finding is a readable sentence; none means the data passed.
enum StockDataAudit {
    /// How far x may sit from a grid point, in grid steps (parsing `-3.70` gives `-74.000000001 × 0.05`).
    static let gridTolerance = 1e-6
    /// A traced characteristic curve may dip below its running maximum by this many chart pixels of density:
    /// a tracing can't resolve less than a pixel (0.006 D on the 250D chart, 0.016 D on the 2383 chart).
    static let tracingTolerancePixels = 1.0
    /// The manifest rounds `xRange` to three decimals.
    static let rangeRounding = 0.0005

    static func findings(for stock: DigitizedStock) -> [String] {
        stock.charts.flatMap { offGrid($0) + outsideTracedRange($0) } + falling(stock.characteristic)
    }

    static func offGrid(_ chart: DigitizedChart) -> [String] {
        let step = chart.entry.gridStep
        let xs = Set(chart.curves.flatMap(\.x)).sorted()
        return xs.filter { abs($0 / step - ($0 / step).rounded()) > gridTolerance }
            .map { "\(chart.file): x = \($0) is off the \(step) grid." }
    }

    /// The digitizer resamples onto grid points up to half a pixel beyond the traced ends.
    static func outsideTracedRange(_ chart: DigitizedChart) -> [String] {
        let slack = 0.5 / chart.entry.xAxis.pixelsPerUnit + rangeRounding
        return chart.curves.compactMap { curve in
            guard let range = chart.entry.curves[curve.name]?.xRange, range.count == 2 else {
                return "\(chart.file): \(curve.name) has no xRange in the manifest."
            }
            let outside = curve.x.filter { $0 < range[0] - slack || $0 > range[1] + slack }
            return outside.isEmpty ? nil : "\(chart.file): \(curve.name) has samples at \(outside) outside its xRange \(range)."
        }
    }

    static func falling(_ chart: DigitizedChart) -> [String] {
        let tolerance = tracingTolerancePixels / chart.entry.yAxis.pixelsPerUnit
        return chart.curves.flatMap { curve in
            var peak = -Double.infinity
            var findings: [String] = []
            for (x, y) in zip(curve.x, curve.y) {
                if y < peak - tolerance {
                    findings.append("\(chart.file): \(curve.name) falls to \(y) at \(x), below its earlier \(peak).")
                }
                peak = max(peak, y)
            }
            return findings
        }
    }
}
