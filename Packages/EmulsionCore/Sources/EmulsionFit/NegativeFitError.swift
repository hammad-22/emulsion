import Foundation

/// Why a negative fit couldn't run or its outputs couldn't be written.
enum NegativeFitError: LocalizedError, Equatable {
    case notACameraNegative(String)
    case missingCameraStops(String)
    case missingLayers(String)
    case invalidBaseStock(path: String, reason: String)
    case fittedStockRejected(String)
    case encodingFailed(String)
    case writeFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .notACameraNegative(let id):
            return "\(id) is not a camera negative (manifest filmType); the negative curve fit doesn't apply."
        case .missingCameraStops(let id):
            return "\(id): the characteristic chart has no camera-stop axis to anchor mid-gray; pass --mid-gray-log-exposure."
        case .missingLayers(let id):
            return "\(id): the characteristic chart needs red, green and blue curves."
        case .invalidBaseStock(let path, let reason):
            return "Base stock \(path) can't be used: \(reason)"
        case .fittedStockRejected(let reason):
            return "The fitted stock fails the engine's validation: \(reason)"
        case .encodingFailed(let reason):
            return "Couldn't encode the fit report: \(reason)"
        case .writeFailed(let path, let reason):
            return "Couldn't write \(path): \(reason)"
        }
    }
}
