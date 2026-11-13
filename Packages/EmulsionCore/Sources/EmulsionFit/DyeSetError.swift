import Foundation

/// Why a negative's dye set couldn't be reconstructed or its conversions fitted.
enum DyeSetError: LocalizedError, Equatable {
    case notACameraNegative(String)
    case missingCurve(stock: String, curve: String)
    case noMidscaleOverlap(String)
    case dyeAmountsDidNotConverge(target: [Double], residual: Double)
    case singularFit(String)

    var errorDescription: String? {
        switch self {
        case .notACameraNegative(let id):
            return "\(id) is not a camera negative (manifest filmType); the negative dye set doesn't apply."
        case .missingCurve(let stock, let curve):
            return "\(stock): no \(curve) curve to build the dye set from."
        case .noMidscaleOverlap(let id):
            return "\(id): the dye, midscale neutral and minimum density curves share no wavelength in the midscale check's span."
        case .dyeAmountsDidNotConverge(let target, let residual):
            let densities = target.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            return "No dye amounts reproduce density (\(densities)) above minimum: Newton stopped at residual \(residual)."
        case .singularFit(let model):
            return "The \(model) fit is singular: its inputs don't span three independent directions."
        }
    }
}
