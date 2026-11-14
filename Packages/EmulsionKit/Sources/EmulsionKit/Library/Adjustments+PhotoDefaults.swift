import EmulsionCore
import Foundation

extension Adjustments {
    /// Seeds are whole numbers below this, so they stay exact in the grain kernel's floats.
    static let grainSeedCount = 1024

    /// The seed comes from the photo's ID, so re-renders and exports match and photos differ.
    static func defaults(for id: UUID, look: Adjustments = Adjustments()) -> Adjustments {
        let seedsPerFirstByte = grainSeedCount / (Int(UInt8.max) + 1)
        var adjustments = look
        adjustments.seed = Double(Int(id.uuid.0) * seedsPerFirstByte + Int(id.uuid.1) % seedsPerFirstByte)
        return adjustments
    }
}
