/// A grid of flat patches, `cell` pixels square, row-major from the top-left. Cells are large
/// enough that demosaic and denoise edges leave each centre untouched.
public struct PatchChart: Sendable {
    private static let minimumCell = 32

    public let patches: [SIMD3<Double>]
    public let cell: Int
    public let columns: Int

    public init(_ patches: [SIMD3<Double>], cell: Int = 48, columns: Int = 8) {
        precondition(!patches.isEmpty, "a chart needs at least one patch")
        precondition(cell >= Self.minimumCell && cell.isMultiple(of: 2), "cells must be even and at least \(Self.minimumCell) px")
        self.patches = patches
        self.cell = cell
        self.columns = min(columns, patches.count)
    }

    public var rows: Int { (patches.count + columns - 1) / columns }
    public var width: Int { columns * cell }
    public var height: Int { rows * cell }

    /// The patch under pixel (x, y), y = 0 the top row; black outside the patches.
    public func value(x: Int, y: Int) -> SIMD3<Double> {
        let index = (y / cell) * columns + x / cell
        return index < patches.count ? patches[index] : .zero
    }

    /// The central quarter (half width, half height) of patch `index` in top-left pixel
    /// coordinates, for an image drawn at `scale` times the chart size.
    public func centre(of index: Int, scale: Double = 1) -> (x: Range<Int>, y: Range<Int>) {
        let size = Double(cell) * scale
        let left = Double(index % columns) * size
        let top = Double(index / columns) * size
        let lower = { (origin: Double) in Int((origin + size / 4).rounded()) }
        let upper = { (origin: Double) in max(lower(origin) + 1, Int((origin + 3 * size / 4).rounded())) }
        return (lower(left)..<upper(left), lower(top)..<upper(top))
    }

    /// Mean of each patch's central quarter in `pixels` (bottom row first, as `Fixtures.linear`
    /// returns them) of an image `width` × `height` drawn from this chart at any scale.
    public func means(of pixels: [SIMD3<Double>], width: Int, height: Int) -> [SIMD3<Double>] {
        let scale = Double(width) / Double(self.width)
        return patches.indices.map { index in
            let (xs, ys) = centre(of: index, scale: scale)
            var sum = SIMD3<Double>.zero
            for y in ys { for x in xs { sum += pixels[(height - 1 - y) * width + x] } }
            return sum / Double(xs.count * ys.count)
        }
    }
}
