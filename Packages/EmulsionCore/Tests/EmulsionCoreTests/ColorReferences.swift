import CoreImage
import EmulsionFixtures
import Testing
import simd

@testable import EmulsionCore

/// Independent colour-science reference vectors for every `InputColorSpace`: code values in,
/// linear Rec.709/D65 working-space light out. Generated offline by
/// `Tools/color-references/generate_input_references.py` into `References/input-transforms.json`.
/// Also the loader of every other table in `References/`.
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

    /// Measured worst case in working-space light is 3.2e-5 relative for both the float64 mirror
    /// and the float32 kernel: colour-science uses the published normalized primary matrices
    /// (e.g. S-Gamut3.Cine, AWG3), the engine derives its matrices from primaries. A swapped
    /// gamut matrix is off by ~0.1. Display encodings also pass `kernelTolerance` after the
    /// inverse film curve.
    static let mirrorTolerance = Tolerance(absolute: 1e-6, relative: 1e-4)
    static let kernelTolerance = Tolerance(absolute: 1e-6, relative: 2e-4)

    /// A 10-bit Y′CbCr patch from `References/video-signal.json` (MOV-80): codes in `range`,
    /// decoded with `matrix`.
    struct VideoSample: Decodable, Sendable, CustomTestStringConvertible {
        let space: InputColorSpace
        let range: String
        let matrix: String
        let patch: String
        let code: SIMD3<Int>
        let working: SIMD3<Double>

        var signal: VideoSignal { VideoSignal(range: range == "legal" ? .legal : .full, matrix: matrix == "bt709" ? .bt709 : .bt2020) }
        var testDescription: String { "\(space.title) \(range) \(patch)" }
    }

    static func videoSamples() throws -> [VideoSample] { try videoTable.get() }

    static func samples(for space: InputColorSpace) throws -> [Sample] {
        let samples = try #require(try table.get()[space.rawValue], "no references for \(space.rawValue)")
        try #require(!samples.isEmpty)
        return samples
    }

    static func spaceNames() throws -> Set<String> { Set(try table.get().keys) }

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
        try JSONDecoder().decode(Table.self, from: reference("input-transforms")).spaces.mapValues(\.samples)
    }

    private struct VideoTable: Decodable { let samples: [VideoSample] }

    private static let videoTable: Result<[VideoSample], any Error> = Result {
        try JSONDecoder().decode(VideoTable.self, from: reference("video-signal")).samples
    }

    /// CIEDE2000 references from `References/delta-e.json` (MOV-37): Sharma, Wu & Dalal (2005)
    /// Lab pairs, Display P3 encoded pairs and the 24-patch chart in the working space.
    struct DeltaE: Decodable, Sendable {
        struct LabPair: Decodable, Sendable {
            let pair: Int
            let lab1: SIMD3<Double>
            let lab2: SIMD3<Double>
            let deltaE: Double
        }
        struct P3Pair: Decodable, Sendable {
            let label: String
            let rgb1: SIMD3<Double>
            let rgb2: SIMD3<Double>
            let lab1: SIMD3<Double>
            let lab2: SIMD3<Double>
            let deltaE: Double
        }
        struct Patch: Decodable, Sendable {
            let name: String
            let linear: SIMD3<Double>
        }
        let labPairs: [LabPair]
        let p3Pairs: [P3Pair]
        let chart24: [Patch]
    }

    static func deltaE() throws -> DeltaE { try deltaETable.get() }
    private static let deltaETable = decoded(DeltaE.self, "delta-e")

    /// The digitized datasheet granularity (MOV-30), from `Tools/grain-reference/granularity`.
    static func granularity() throws -> GrainReference { try granularityTable.get() }
    private static let granularityTable = decoded(GrainReference.self, "granularity")

    /// Boolean-model grain (Selwyn scaling, W(0)), from `Tools/grain-reference/boolean-model`.
    static func grainBooleanModel() throws -> GrainReference.BooleanModel { try grainBooleanModelTable.get() }
    private static let grainBooleanModelTable = decoded(GrainReference.BooleanModel.self, "grain-boolean-model")

    /// The derived halation profile and its fits (MOV-32), from `Tools/halation-kernel`.
    static func halationKernel() throws -> HalationReference { try halationKernelTable.get() }
    private static let halationKernelTable = decoded(HalationReference.self, "halation-kernel")

    /// `References/<name>.json` with snake_case keys, decoded once by the caller's stored `let`.
    private static func decoded<T: Decodable>(_ type: T.Type, _ name: String) -> Result<T, any Error> {
        Result {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(type, from: reference(name))
        }
    }

    private static func reference(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "References") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
