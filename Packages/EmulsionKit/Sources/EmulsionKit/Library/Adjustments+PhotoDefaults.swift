import EmulsionCore
import Foundation

extension Adjustments {
    /// Grain seeds are whole numbers below this: small whole numbers keep float precision exact
    /// in the grain kernel.
    static let grainSeedCount = 1024

    /// The starting edit for a photo: `look` (the default look unless a recipe was chosen), with
    /// a grain seed (0 ..< `grainSeedCount`) derived from the photo's ID so re-renders, exports
    /// and resets match, and photos differ.
    static func defaults(for id: UUID, look: Adjustments = Adjustments()) -> Adjustments {
        let seedsPerFirstByte = grainSeedCount / (Int(UInt8.max) + 1)
        var adjustments = look
        adjustments.seed = Double(Int(id.uuid.0) * seedsPerFirstByte + Int(id.uuid.1) % seedsPerFirstByte)
        return adjustments
    }
}
