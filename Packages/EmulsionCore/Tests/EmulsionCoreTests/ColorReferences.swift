import CoreImage
import EmulsionFixtures
import Testing
import simd

@testable import EmulsionCore

/// Independent colour-science reference vectors for every `InputColorSpace`: code values in,
/// linear Rec.709/D65 working-space light out. Generated offline by
/// `Tools/color-references/generate_input_references.py` into `References/input-transforms.json`.
enum ColorReferences {
    struct Sample: Decodable, Sendable {
        let label: String
        let code: SIMD3<Double>
        let working: SIMD3<Double>
    }

    struct Tolerance: Sendable {
        let absolute: Double
        let relative: Double
    }

    /// Measured worst case is 3.2e-5 relative for both the float64 mirror and the float32
    /// kernel: colour-science uses the published normalized primary matrices (e.g.
    /// S-Gamut3.Cine, AWG3), the engine derives its matrices from primaries. A swapped gamut
    /// matrix is off by ~0.1.
    static let mirrorTolerance = Tolerance(absolute: 1e-6, relative: 1e-4)
    static let kernelTolerance = Tolerance(absolute: 1e-6, relative: 2e-4)

    static func samples(for space: InputColorSpace) throws -> [Sample] {
        let samples = try #require(try table.get()[space.rawValue], "no references for \(space.rawValue)")
        try #require(!samples.isEmpty)
        return samples
    }

    /// A one-row image of the samples' raw code values (no color matching), left to right.
    static func encodedImage(_ samples: [Sample]) -> CIImage {
        Fixtures.row(samples.map { SIMD3<Float>($0.code) }, space: nil)
    }

    static func expectMatch(
        _ actual: SIMD3<Double>, _ expected: SIMD3<Double>, _ tolerance: Tolerance, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let allowed = tolerance.absolute + tolerance.relative * simd_abs(expected)
        #expect(all(simd_abs(actual - expected) .<= allowed), "\(label): \(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    private struct Table: Decodable {
        struct Space: Decodable { let samples: [Sample] }
        let spaces: [String: Space]
    }

    private static let table: Result<[String: [Sample]], any Error> = Result {
        guard let url = Bundle.module.url(forResource: "input-transforms", withExtension: "json", subdirectory: "References") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Table.self, from: Data(contentsOf: url)).spaces.mapValues(\.samples)
    }
}
