import Foundation
import simd

/// The versioned, serialisable description of a negative → print stock: the parameters of
/// `FilmModel` plus where they came from. Stock files are JSON (`Resources/Stocks/*.json`);
/// `FilmModel(stock:)` validates one and calibrates its printer lights.
///
/// Matrices are stored as three rows of three, row-major, as in `simd_double3x3(rows:)`.
/// Exposures and offsets are log10 exposure relative to scene mid-gray (18%); gammas are
/// slopes in density per log10 exposure.
public struct FilmStock: Codable, Sendable, Equatable {
    /// The only stock file format this engine reads.
    public static let supportedFormatVersion = 1

    public let formatVersion: Int
    public var name: String
    public var provenance: Provenance
    public var negative: Negative
    public var print: Print
    public var rendering: Rendering

    public init(name: String, provenance: Provenance, negative: Negative, print: Print, rendering: Rendering) {
        self.formatVersion = Self.supportedFormatVersion
        self.name = name
        self.provenance = provenance
        self.negative = negative
        self.print = print
        self.rendering = rendering
    }

    /// Where the parameters came from: hand-tuned or fitted, from what, by which tool.
    public struct Provenance: Codable, Sendable, Equatable {
        public var source: String
        /// ISO 8601 date of the fit, when fitted.
        public var fitDate: String?
        public var tool: String?
        /// SHA-256 (hex) of the source data the stock was fitted to.
        public var sourceSHA256: String?
        /// Named fit errors, free-form, as the fit tool reports them.
        public var fitResiduals: [String: Double]?
        public var notes: [String]

        public init(
            source: String, fitDate: String? = nil, tool: String? = nil, sourceSHA256: String? = nil,
            fitResiduals: [String: Double]? = nil, notes: [String] = []
        ) {
            self.source = source
            self.fitDate = fitDate
            self.tool = tool
            self.sourceSHA256 = sourceSHA256
            self.fitResiduals = fitResiduals
            self.notes = notes
        }
    }

    /// Camera negative: layer sensitivities and characteristic (H&D) curves.
    public struct Negative: Codable, Sendable, Equatable {
        /// Layer spectral overlap as a 3×3 mix of scene light; each row sums to 1.
        public var sensitivity: simd_double3x3
        /// Curve slope at its center, density per log10 exposure (R, G, B layers).
        public var gamma: SIMD3<Double>
        /// Density span of each layer's curve.
        public var densityRange: Double
        /// log10 exposure of each curve's center relative to mid-gray.
        public var exposureOffset: SIMD3<Double>

        public init(sensitivity: simd_double3x3, gamma: SIMD3<Double>, densityRange: Double, exposureOffset: SIMD3<Double>) {
            self.sensitivity = sensitivity
            self.gamma = gamma
            self.densityRange = densityRange
            self.exposureOffset = exposureOffset
        }

        private enum CodingKeys: String, CodingKey { case sensitivity, gamma, densityRange, exposureOffset }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sensitivity = try c.decodeMatrix(forKey: .sensitivity)
            gamma = try c.decode(SIMD3<Double>.self, forKey: .gamma)
            densityRange = try c.decode(Double.self, forKey: .densityRange)
            exposureOffset = try c.decode(SIMD3<Double>.self, forKey: .exposureOffset)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeMatrix(sensitivity, forKey: .sensitivity)
            try c.encode(gamma, forKey: .gamma)
            try c.encode(densityRange, forKey: .densityRange)
            try c.encode(exposureOffset, forKey: .exposureOffset)
        }
    }

    /// Print stock: characteristic curves and dye cross-absorption.
    public struct Print: Codable, Sendable, Equatable {
        /// Curve slope at its center, density per log10 print exposure (R, G, B layers).
        public var gamma: SIMD3<Double>
        /// Paper-white density (base + fog).
        public var minimumDensity: Double
        /// Density span above `minimumDensity`.
        public var densityRange: Double
        /// Richards shape of the curve (1 = symmetric logistic).
        public var shape: Double
        /// Unwanted absorptions of the print dyes as a 3×3 mix; each row sums to 1.
        public var dyes: simd_double3x3

        public init(gamma: SIMD3<Double>, minimumDensity: Double, densityRange: Double, shape: Double, dyes: simd_double3x3) {
            self.gamma = gamma
            self.minimumDensity = minimumDensity
            self.densityRange = densityRange
            self.shape = shape
            self.dyes = dyes
        }

        private enum CodingKeys: String, CodingKey { case gamma, minimumDensity, densityRange, shape, dyes }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            gamma = try c.decode(SIMD3<Double>.self, forKey: .gamma)
            minimumDensity = try c.decode(Double.self, forKey: .minimumDensity)
            densityRange = try c.decode(Double.self, forKey: .densityRange)
            shape = try c.decode(Double.self, forKey: .shape)
            dyes = try c.decodeMatrix(forKey: .dyes)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(gamma, forKey: .gamma)
            try c.encode(minimumDensity, forKey: .minimumDensity)
            try c.encode(densityRange, forKey: .densityRange)
            try c.encode(shape, forKey: .shape)
            try c.encodeMatrix(dyes, forKey: .dyes)
        }
    }

    /// Display rendering choices outside the photochemical chain.
    public struct Rendering: Codable, Sendable, Equatable {
        /// Blend toward ratio-preserving highlights, 0...1 (artistic, see `FilmModel`).
        public var highlightChromaRetention: Double
        /// Display-linear value scene mid-gray is timed to, on every channel.
        public var middleGrayOut: Double

        public init(highlightChromaRetention: Double, middleGrayOut: Double) {
            self.highlightChromaRetention = highlightChromaRetention
            self.middleGrayOut = middleGrayOut
        }
    }

    // MARK: Files

    private enum CodingKeys: String, CodingKey { case formatVersion, name, provenance, negative, print, rendering }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == Self.supportedFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion, in: c,
                debugDescription: "Unsupported format version \(formatVersion); this engine reads version \(Self.supportedFormatVersion).")
        }
        name = try c.decode(String.self, forKey: .name)
        provenance = try c.decode(Provenance.self, forKey: .provenance)
        negative = try c.decode(Negative.self, forKey: .negative)
        print = try c.decode(Print.self, forKey: .print)
        rendering = try c.decode(Rendering.self, forKey: .rendering)
    }

    /// Reads a stock file. Throws `EmulsionError.invalidStock` for malformed or unsupported files.
    public init(data: Data) throws(EmulsionError) {
        do {
            self = try JSONDecoder().decode(FilmStock.self, from: data)
        } catch let error as DecodingError {
            throw .invalidStock(error.stockFileReason)
        } catch {
            throw .invalidStock(error.localizedDescription)
        }
    }

    /// The stock file: pretty-printed with sorted keys, so the same stock always encodes to the same bytes.
    public func encoded() throws(EmulsionError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw .invalidStock(error.localizedDescription)
        }
    }

    /// A stock shipped with the engine, `Resources/Stocks/<name>.json`.
    public static func bundled(named name: String) throws(EmulsionError) -> FilmStock {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { throw .invalidStock("No bundled stock named \(name).") }
        return try FilmStock(data: data)
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeMatrix(forKey key: Key) throws -> simd_double3x3 {
        let rows = try decode([SIMD3<Double>].self, forKey: key)
        guard rows.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected 3 rows, found \(rows.count).")
        }
        return simd_double3x3(rows: rows)
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodeMatrix(_ m: simd_double3x3, forKey key: Key) throws {
        try encode(m.rows, forKey: key)
    }
}

extension DecodingError {
    /// The failing key path and the decoder's explanation, for `EmulsionError.invalidStock`.
    fileprivate var stockFileReason: String {
        let context: Context
        switch self {
        case .dataCorrupted(let c), .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c): context = c
        @unknown default: return localizedDescription
        }
        let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
