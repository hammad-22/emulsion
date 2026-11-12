import Foundation
import simd

/// The versioned, serialisable description of a negative → print stock: the parameters of
/// `FilmModel` plus where they came from. Stock files are JSON (`Resources/Stocks/*.json`);
/// `FilmModel(stock:)` validates one and calibrates its printer lights.
///
/// Matrices are stored as three rows of three, row-major, as in `simd_double3x3(rows:)`.
/// Exposures and widths are log10 exposure relative to scene mid-gray (18%); gammas are
/// slopes per log10 exposure (dye amount for the negative, density for the print).
public struct FilmStock: Codable, Sendable, Equatable {
    /// The only stock file format this engine reads.
    public static let supportedFormatVersion = 2

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
        /// The fit tool's id of the datasheet stock the parameters were fitted to.
        public var sourceStock: String?
        /// SHA-256 (hex) of the source data the stock was fitted to.
        public var sourceSHA256: String?
        /// Named fit errors, free-form, as the fit tool reports them.
        public var fitResiduals: [String: Double]?
        public var notes: [String]

        public init(
            source: String, fitDate: String? = nil, tool: String? = nil, sourceStock: String? = nil, sourceSHA256: String? = nil,
            fitResiduals: [String: Double]? = nil, notes: [String] = []
        ) {
            self.source = source
            self.fitDate = fitDate
            self.tool = tool
            self.sourceStock = sourceStock
            self.sourceSHA256 = sourceSHA256
            self.fitResiduals = fitResiduals
            self.notes = notes
        }
    }

    /// Camera negative: layer sensitivities, characteristic curves in dye amount, and printing density per unit dye
    /// (see `FilmModel.negativeDyeAmount`). Per layer: red-, green-, blue-sensitive (cyan, magenta, yellow dye).
    public struct Negative: Codable, Sendable, Equatable {
        /// Layer spectral overlap as a 3×3 mix of scene light; each row sums to 1.
        public var sensitivity: simd_double3x3
        /// Straight-line slope, dye amount per log10 exposure.
        public var gamma: SIMD3<Double>
        /// Where the straight line meets zero dye amount, log10 exposure relative to mid-gray.
        public var toeExposure: SIMD3<Double>
        /// How gradually the toe bends, log10 exposure.
        public var toeWidth: SIMD3<Double>
        /// Where the straight line meets the shoulder's plateau, log10 exposure relative to mid-gray.
        public var shoulderExposure: SIMD3<Double>
        /// How gradually the shoulder bends, log10 exposure.
        public var shoulderWidth: SIMD3<Double>
        /// Printing density per unit dye: rows printing density R, G, B; columns cyan, magenta, yellow.
        public var printingDensity: simd_double3x3

        public init(
            sensitivity: simd_double3x3, gamma: SIMD3<Double>, toeExposure: SIMD3<Double>, toeWidth: SIMD3<Double>,
            shoulderExposure: SIMD3<Double>, shoulderWidth: SIMD3<Double>, printingDensity: simd_double3x3
        ) {
            self.sensitivity = sensitivity
            self.gamma = gamma
            self.toeExposure = toeExposure
            self.toeWidth = toeWidth
            self.shoulderExposure = shoulderExposure
            self.shoulderWidth = shoulderWidth
            self.printingDensity = printingDensity
        }

        private enum CodingKeys: String, CodingKey {
            case sensitivity, gamma, toeExposure, toeWidth, shoulderExposure, shoulderWidth, printingDensity
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sensitivity = try c.decodeMatrix(forKey: .sensitivity)
            gamma = try c.decode(SIMD3<Double>.self, forKey: .gamma)
            toeExposure = try c.decode(SIMD3<Double>.self, forKey: .toeExposure)
            toeWidth = try c.decode(SIMD3<Double>.self, forKey: .toeWidth)
            shoulderExposure = try c.decode(SIMD3<Double>.self, forKey: .shoulderExposure)
            shoulderWidth = try c.decode(SIMD3<Double>.self, forKey: .shoulderWidth)
            printingDensity = try c.decodeMatrix(forKey: .printingDensity)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeMatrix(sensitivity, forKey: .sensitivity)
            try c.encode(gamma, forKey: .gamma)
            try c.encode(toeExposure, forKey: .toeExposure)
            try c.encode(toeWidth, forKey: .toeWidth)
            try c.encode(shoulderExposure, forKey: .shoulderExposure)
            try c.encode(shoulderWidth, forKey: .shoulderWidth)
            try c.encodeMatrix(printingDensity, forKey: .printingDensity)
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
        try FilmStock(data: bundledFile(named: name))
    }

    /// The bytes of a shipped stock file, as the apps carry it.
    package static func bundledFile(named name: String) throws(EmulsionError) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { throw .invalidStock("No bundled stock named \(name).") }
        return data
    }
}

extension FilmStock.Negative {
    /// Straight-line slope of printing density per log10 exposure, per channel: printingDensity · gamma.
    package var printingDensityGamma: SIMD3<Double> { printingDensity * gamma }
}

extension FilmStock {
    /// Print gamma × the negative's printing-density gamma, per channel: the gray scale's overall contrast.
    package var systemContrast: SIMD3<Double> { print.gamma * negative.printingDensityGamma }

    /// Sets each channel's print gamma so its system contrast is `contrast`: a print stock's layer contrasts are matched
    /// to the printing-density contrasts of the negatives it prints (SMPTE RP 180-1999 Introduction).
    package mutating func rebalancePrintGamma(systemContrast contrast: Double) {
        print.gamma = contrast / negative.printingDensityGamma
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
