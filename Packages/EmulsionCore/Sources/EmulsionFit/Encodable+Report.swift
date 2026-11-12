import Foundation

extension Encodable {
    /// Pretty, sorted-key JSON, so two runs over the same data write byte-identical reports.
    func reportJSON() throws(NegativeFitError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw .encodingFailed(error.localizedDescription)
        }
    }
}
