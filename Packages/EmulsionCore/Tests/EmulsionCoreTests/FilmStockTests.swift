import CryptoKit
import Foundation
import Testing
import simd

@testable import EmulsionCore

struct FilmStockTests {
    @Test func defaultStockRendersBitIdenticalToBeforeStockFiles() {
        // Recorded from `main` at commit 1bc3532, when the parameters were hard-coded in FilmModel.
        #expect(Self.renderFingerprint(FilmLook.stock) == "5752d668f795198e928296ee1d632d20fb49f2ca7ff6b4f9e0ad8408f5e208c4")
    }

    @Test func bundledDefaultHoldsTheEngineDefaults() throws {
        #expect(try FilmStock.bundled(named: "emulsion-default") == .engineDefault)
    }

    @Test func stockRoundTripsThroughJSON() throws {
        var stock = FilmStock.engineDefault
        stock.provenance = .init(
            source: "Synthetic fit", fitDate: "2026-11-10", tool: "test", sourceSHA256: String(repeating: "0", count: 64),
            fitResiduals: ["rmsDensity": 0.004], notes: ["a", "b"])
        #expect(try FilmStock(data: stock.encoded()) == stock)
    }

    @Test func encodingIsStable() throws {
        let stock = FilmStock.engineDefault
        #expect(try stock.encoded() == FilmStock(data: stock.encoded()).encoded())
    }

    @Test func missingOptionalProvenanceIsOmitted() throws {
        let json = try #require(String(data: FilmStock.engineDefault.encoded(), encoding: .utf8))
        #expect(!json.contains("fitDate") && !json.contains("null"))
    }

    @Test func changedPrintGammasStillPrintMidGrayAtMiddleGrayOut() throws {
        var stock = FilmStock.engineDefault
        stock.print.gamma = SIMD3(2.6, 2.0, 1.8)
        let model = try FilmModel(stock: stock)
        let midGray = model.render(SIMD3(repeating: 0.18))
        for c in 0..<3 { #expect(abs(midGray[c] - stock.rendering.middleGrayOut) <= 1e-6) }
        #expect(model.printerLights != FilmLook.stock.printerLights)
    }

    @Test func scalarNegativeCurveMatchesTheLayerCurves() {
        let model = FilmLook.stock
        let logE = SIMD3(-1.3, 0.2, 1.7)
        let layers = model.negativeDensity(logE)
        for c in 0..<3 {
            let scalar = FilmModel.negativeDensity(
                logExposure: logE[c], gamma: model.negativeGamma[c], densityRange: model.negativeRange,
                exposureOffset: model.negativeOffset[c])
            #expect(scalar.bitPattern == layers[c].bitPattern)
        }
    }

    @Test(arguments: InvalidStock.allCases)
    func invalidStockIsRejected(_ invalid: InvalidStock) {
        #expect {
            try FilmModel(stock: invalid.stock)
        } throws: { error in
            guard case .invalidStock = error as? EmulsionError else { return false }
            return true
        }
    }

    @Test func invalidStockKeepsItsReasonOutOfTheAlertText() throws {
        var stock = FilmStock.engineDefault
        stock.negative.gamma = SIMD3(0, 0.62, 0.65)
        do {
            _ = try FilmModel(stock: stock)
            Issue.record("a zero negative gamma must be rejected")
        } catch {
            #expect(error.failureReason?.contains("gamma") == true)
            #expect(error.errorDescription?.contains("gamma") == false)
            #expect(error.developerDescription.contains("gamma"))
        }
    }

    @Test(arguments: InvalidStockFile.allCases)
    func invalidStockFileIsRejected(_ invalid: InvalidStockFile) throws {
        let json = try #require(String(data: FilmStock.engineDefault.encoded(), encoding: .utf8))
        let edited = invalid.edit(json)
        #expect(edited != json, "the edit must apply to the canonical encoding")
        #expect {
            try FilmStock(data: Data(edited.utf8))
        } throws: { error in
            guard case .invalidStock = error as? EmulsionError else { return false }
            return true
        }
    }
}

enum InvalidStock: CaseIterable, CustomTestStringConvertible {
    case notANumber, infinity, zeroNegativeGamma, zeroPrintGamma, zeroNegativeRange, zeroPrintRange, zeroPrintShape
    case negativeMinimumDensity, middleGrayOutOfRange, retentionOutOfRange, sensitivityRowNotOne, dyeRowNotOne
    case calibrationCannotConverge

    var testDescription: String { "\(self)" }

    var stock: FilmStock {
        var s = FilmStock.engineDefault
        switch self {
        case .notANumber: s.negative.exposureOffset.y = .nan
        case .infinity: s.print.densityRange = .infinity
        case .zeroNegativeGamma: s.negative.gamma.x = 0
        case .zeroPrintGamma: s.print.gamma.z = 0
        case .zeroNegativeRange: s.negative.densityRange = 0
        case .zeroPrintRange: s.print.densityRange = 0
        case .zeroPrintShape: s.print.shape = 0
        case .negativeMinimumDensity: s.print.minimumDensity = -0.01
        case .middleGrayOutOfRange: s.rendering.middleGrayOut = 1
        case .retentionOutOfRange: s.rendering.highlightChromaRetention = 1.2
        case .sensitivityRowNotOne: s.negative.sensitivity[0, 1] += 0.01
        case .dyeRowNotOne: s.print.dyes[2, 2] -= 0.01
        // A nearly flat print curve stays near density 0.8: mid-gray can't print as bright as 0.17.
        case .calibrationCannotConverge: s.print.gamma = SIMD3(repeating: 0.01)
        }
        return s
    }
}

enum InvalidStockFile: CaseIterable, CustomTestStringConvertible {
    case unsupportedFormatVersion, shortGamma, twoMatrixRows, longMatrixRow, missingKey

    var testDescription: String { "\(self)" }

    func edit(_ json: String) -> String {
        switch self {
        case .unsupportedFormatVersion: json.replacingOccurrences(of: #""formatVersion" : 1"#, with: #""formatVersion" : 2"#)
        case .shortGamma: json.replacingOccurrences(of: "0.6,\n      0.62,", with: "0.6,")
        case .twoMatrixRows: json.replacingOccurrences(of: "[\n        1.07,\n        -0.05,\n        -0.02\n      ],", with: "")
        case .longMatrixRow: json.replacingOccurrences(of: "1.07,", with: "1.07, 0.0,")
        case .missingKey: json.replacingOccurrences(of: #""minimumDensity" : 0.06,"#, with: "")
        }
    }
}

extension FilmStock {
    /// Today's engine constants, written out independently of the bundled file.
    static let engineDefault = FilmStock(
        name: "Emulsion Default",
        provenance: .init(
            source: "Hand-tuned in the engine; not fitted to any datasheet.",
            notes: ["Artistic/approximated parameters, see docs/FILM-THEORY.md §7."]),
        negative: .init(
            sensitivity: simd_double3x3(rows: [SIMD3(1.07, -0.05, -0.02), SIMD3(-0.04, 1.08, -0.04), SIMD3(-0.01, -0.07, 1.08)]),
            gamma: SIMD3(0.60, 0.62, 0.65), densityRange: 3.0, exposureOffset: SIMD3(0.45, 0.45, 0.45)),
        print: .init(
            gamma: SIMD3(2.20, 2.15, 2.05), minimumDensity: 0.06, densityRange: 3.3, shape: 0.5,
            dyes: simd_double3x3(rows: [SIMD3(0.94, 0.05, 0.01), SIMD3(0.04, 0.90, 0.06), SIMD3(0.01, 0.07, 0.92)])),
        rendering: .init(highlightChromaRetention: 0.6, middleGrayOut: 0.17))
}

extension FilmStockTests {
    /// SHA-256 over the bit patterns of a fixed set of renders, the printer lights and the kernel arguments.
    static func renderFingerprint(_ model: FilmModel) -> String {
        var bits = [UInt64]()
        func append(_ v: SIMD3<Double>) { bits += [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern] }
        for stops in stride(from: -8.0, through: 8.0, by: 0.25) {
            append(model.render(SIMD3(repeating: 0.18 * pow(2, stops))))
        }
        var seed: UInt32 = 107
        func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24)
        }
        for i in 0..<435 {
            let color = SIMD3(next(), next(), next()) * 0.18 * pow(2, 16 * next() - 8)
            append(model.render(color))
            if i.isMultiple(of: 10) {
                append(model.render(color, lights: SIMD3(0.05, -0.05, 0.1), saturation: 1.3))
            }
        }
        append(model.printerLights)
        for vector in model.kernelArguments(lights: SIMD3(0.05, -0.05, 0.1), exposure: 0.5, saturation: 1.3) {
            bits += (0..<vector.count).map { Double(vector.value(at: $0)).bitPattern }
        }
        let data = bits.withUnsafeBytes { Data($0) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
