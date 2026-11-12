/// One traced curve of a datasheet chart: only the rows where the chart draws it, x ascending.
struct DigitizedCurve: Sendable, Equatable {
    let name: String
    let x: [Double]
    let y: [Double]
}
