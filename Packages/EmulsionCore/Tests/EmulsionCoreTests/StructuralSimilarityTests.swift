import CoreImage
import Foundation
import Testing

@testable import EmulsionCore

struct StructuralSimilarityTests {
    private struct Reference: Decodable {
        struct Case: Decodable {
            let name: String
            let ssim: Double
        }
        let width: Int
        let height: Int
        let cases: [Case]
    }

    /// The planes of `Tools/color-references/generate_ssim_references.py`, row `i`, column `j`.
    private static func base(_ i: Double, _ j: Double) -> Double {
        50 + 25 * sin(0.3 * i) * cos(0.2 * j) + 10 * (Double((7 * Int(i) + 13 * Int(j)) % 11) / 11)
    }

    private static let variants: [String: @Sendable (Double, Double) -> Double] = [
        "identical": base,
        "contrast and offset": { 0.9 * base($0, $1) + 5 },
        "added pattern": { base($0, $1) + 8 * sin(1.7 * $0 + 0.9 * $1) },
        "flattened": { _, _ in 50 },
        "texture removed": { 50 + 25 * sin(0.3 * $0) * cos(0.2 * $1) + 5 },
    ]

    /// Against scikit-image 0.26 (`References/ssim.json`). Measured largest difference 2e-6 (this
    /// implementation works in Float).
    @Test func matchesScikitImage() throws {
        let reference = try JSONDecoder().decode(Reference.self, from: ColorReferences.reference("ssim"))
        func plane(_ f: (Double, Double) -> Double) -> [Float] {
            (0..<reference.height).flatMap { i in (0..<reference.width).map { j in Float(f(Double(i), Double(j))) } }
        }
        let x = plane(Self.base)
        for c in reference.cases {
            let variant = try #require(Self.variants[c.name], "no plane for \(c.name)")
            let ssim = StructuralSimilarity.index(x, plane(variant), width: reference.width, height: reference.height)
            print(String(format: "SSIM %@: %.6f (scikit-image %.6f)", c.name, ssim, c.ssim))
            #expect(abs(ssim - c.ssim) <= 1e-5, "\(c.name): \(ssim) vs \(c.ssim)")
        }
    }
}
