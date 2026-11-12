import Foundation
import Testing
import simd

@testable import EmulsionCore

struct FilmStockTests {
    /// Pins the default stock's look at a handful of chromatic inputs (display-linear P3, before the gamut fit). The
    /// earlier pin, bit-identical to the engine before stock files, was retired when the default's negative was fitted
    /// to the 250D datasheet (MOV-25): the look changed on purpose. Values recorded from this commit's engine.
    @Test(arguments: [
        (SIMD3(0.18, 0.18, 0.18), SIMD3(0.17000000000000007, 0.17000000000000007, 0.16999999999999982)),
        (SIMD3(0.40, 0.20, 0.13), SIMD3(0.36993044991474383, 0.19463700419777452, 0.12120576504022522)),
        (SIMD3(0.05, 0.12, 0.30), SIMD3(0.02451369480675786, 0.09200677713732108, 0.2409896810652891)),
        (SIMD3(0.02, 0.01, 0.01), SIMD3(0.006922726087520104, 0.004052342913380471, 0.0036608580872483447)),
        (SIMD3(1.80, 1.20, 0.30), SIMD3(0.8147603833611772, 0.6151174848019969, 0.22386845728808275)),
    ])
    func defaultStockRendersItsPinnedLook(_ scene: SIMD3<Double>, _ pinned: SIMD3<Double>) {
        let rendered = FilmLook.stock.render(scene)
        for c in 0..<3 { #expect(abs(rendered[c] - pinned[c]) < 1e-9, "channel \(c): \(rendered)") }
    }

    @Test func midGrayRendersMiddleGrayOut() {
        let midGray = FilmLook.stock.render(SIMD3(repeating: 0.18))
        for c in 0..<3 { #expect(abs(midGray[c] - FilmLook.stock.middleGrayOut) <= 1e-6) }
    }

    /// Largest R, G, B spread of the default's gray scale from −6 to +5 stops, display-linear: measured 0.0030 at +3
    /// stops (docs/ENGINE.md).
    static let neutralScaleSpread = 0.004

    @Test(arguments: Array(stride(from: -6.0, through: 5.0, by: 0.5)))
    func neutralScaleStaysNeutral(_ stops: Double) {
        let gray = FilmLook.stock.render(SIMD3(repeating: 0.18 * pow(2, stops)))
        #expect(gray.max() - gray.min() < Self.neutralScaleSpread, "\(gray)")
    }

    @Test func bundledDefaultPassesValidation() throws {
        _ = try FilmModel(stock: FilmStock.bundledDefault())
    }

    @Test func stockRoundTripsThroughJSON() throws {
        var stock = try FilmStock.bundledDefault()
        stock.provenance = .init(
            source: "Synthetic fit", fitDate: "2026-11-10", tool: "test", sourceSHA256: String(repeating: "0", count: 64),
            fitResiduals: ["rmsDensity": 0.004], notes: ["a", "b"])
        #expect(try FilmStock(data: stock.encoded()) == stock)
    }

    @Test func encodingIsStable() throws {
        let stock = try FilmStock.bundledDefault()
        #expect(try stock.encoded() == FilmStock(data: stock.encoded()).encoded())
    }

    @Test func missingOptionalProvenanceIsOmitted() throws {
        var stock = try FilmStock.bundledDefault()
        stock.provenance = .init(source: "Hand-tuned")
        let json = try #require(String(data: stock.encoded(), encoding: .utf8))
        #expect(!json.contains("fitDate") && !json.contains("null"))
    }

    @Test func changedPrintGammasStillPrintMidGrayAtMiddleGrayOut() throws {
        var stock = try FilmStock.bundledDefault()
        stock.print.gamma = SIMD3(2.6, 2.0, 1.8)
        let model = try FilmModel(stock: stock)
        let midGray = model.render(SIMD3(repeating: 0.18))
        for c in 0..<3 { #expect(abs(midGray[c] - stock.rendering.middleGrayOut) <= 1e-6) }
        #expect(model.printerLights != FilmLook.stock.printerLights)
    }

    @Test func scalarNegativeCurveMatchesTheLayerCurves() {
        let model = FilmLook.stock
        let logE = SIMD3(-1.3, 0.2, 1.7)
        let layers = model.negativeDyeAmount(logE)
        for c in 0..<3 {
            let scalar = FilmModel.negativeDyeAmount(
                logExposure: logE[c], gamma: model.negativeGamma[c], toeExposure: model.negativeToeExposure[c],
                toeWidth: model.negativeToeWidth[c], shoulderExposure: model.negativeShoulderExposure[c],
                shoulderWidth: model.negativeShoulderWidth[c])
            #expect(scalar.bitPattern == layers[c].bitPattern)
        }
        #expect(model.negativePrintingDensity(logE) == model.printingDensity * layers)
    }

    @Test(arguments: InvalidStock.allCases)
    func invalidStockIsRejected(_ invalid: InvalidStock) throws {
        let stock = try invalid.stock()
        #expect {
            try FilmModel(stock: stock)
        } throws: { error in
            guard case .invalidStock(let reason) = error as? EmulsionError else { return false }
            return reason.contains(invalid.reasonMentions)
        }
    }

    @Test func invalidStockKeepsItsReasonOutOfTheAlertText() throws {
        var stock = try FilmStock.bundledDefault()
        stock.negative.gamma.x = 0
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
        let edited = try invalid.edit(FilmStock.bundledDefault().encoded())
        #expect {
            try FilmStock(data: edited)
        } throws: { error in
            guard case .invalidStock = error as? EmulsionError else { return false }
            return true
        }
    }

    /// The format before MOV-25 (logistic negative, no printing-density matrix) is not migrated: the only such file was
    /// the bundled default.
    @Test func versionOneStockFileIsRejectedNamingTheVersion() {
        let versionOne = """
            {"formatVersion": 1, "name": "Emulsion Default", "provenance": {"source": "Hand-tuned", "notes": []},
             "negative": {"sensitivity": [[1.07, -0.05, -0.02], [-0.04, 1.08, -0.04], [-0.01, -0.07, 1.08]],
                          "gamma": [0.60, 0.62, 0.65], "densityRange": 3.0, "exposureOffset": [0.45, 0.45, 0.45]},
             "print": {"gamma": [2.20, 2.15, 2.05], "minimumDensity": 0.06, "densityRange": 3.3, "shape": 0.5,
                       "dyes": [[0.94, 0.05, 0.01], [0.04, 0.90, 0.06], [0.01, 0.07, 0.92]]},
             "rendering": {"highlightChromaRetention": 0.6, "middleGrayOut": 0.17}}
            """
        #expect {
            try FilmStock(data: Data(versionOne.utf8))
        } throws: { error in
            guard case .invalidStock(let reason) = error as? EmulsionError else { return false }
            return reason.contains("version 1") && reason.contains("version \(FilmStock.supportedFormatVersion)")
        }
    }
}

enum InvalidStock: CaseIterable, CustomTestStringConvertible {
    case notANumber, infinity, zeroNegativeGamma, zeroPrintGamma, zeroToeWidth, zeroShoulderWidth, shoulderBelowToe
    case negativeCurveFalls
    case printingDensityNotFinite, printingDensityDiagonalNotPositive, printingDensitySingular, printingDensityGammaNotPositive
    case zeroPrintRange, zeroPrintShape, negativeMinimumDensity, middleGrayOutOfRange, retentionOutOfRange
    case sensitivityRowNotOne, dyeRowNotOne, calibrationCannotConverge

    var testDescription: String { "\(self)" }

    func stock() throws -> FilmStock {
        var s = try FilmStock.bundledDefault()
        switch self {
        case .notANumber: s.negative.toeExposure.y = .nan
        case .infinity: s.print.densityRange = .infinity
        case .zeroNegativeGamma: s.negative.gamma.x = 0
        case .zeroPrintGamma: s.print.gamma.z = 0
        case .zeroToeWidth: s.negative.toeWidth.y = 0
        case .zeroShoulderWidth: s.negative.shoulderWidth.z = 0
        case .shoulderBelowToe: s.negative.shoulderExposure.x = s.negative.toeExposure.x
        // A toe far narrower than the shoulder: the shoulder's bend starts pulling the curve down below the toe.
        case .negativeCurveFalls:
            s.negative.toeExposure.y = 0
            s.negative.toeWidth.y = 0.02
            s.negative.shoulderExposure.y = 0.5
            s.negative.shoulderWidth.y = 2.0
        case .printingDensityNotFinite: s.negative.printingDensity[1, 0] = .infinity
        case .printingDensityDiagonalNotPositive: s.negative.printingDensity[1, 1] = 0
        // Two equal rows: positive diagonal, zero determinant.
        case .printingDensitySingular:
            s.negative.printingDensity = simd_double3x3(rows: [SIMD3(1, 0.5, 0), SIMD3(1, 0.5, 0), SIMD3(0, 0, 1)])
        // Positive diagonal and invertible, but red printing density falls as neutral exposure rises.
        case .printingDensityGammaNotPositive:
            s.negative.printingDensity = simd_double3x3(rows: [
                SIMD3(0.9, -1.0, 0), SIMD3(0.1, 0.85, 0.09), SIMD3(0.05, 0.07, 0.85),
            ])
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

    /// A word the rejection's reason must contain.
    var reasonMentions: String {
        switch self {
        case .notANumber, .infinity, .printingDensityNotFinite: "finite"
        case .zeroNegativeGamma: "negative gamma"
        case .zeroPrintGamma: "print gamma"
        case .zeroToeWidth: "toe width"
        case .zeroShoulderWidth: "shoulder width"
        case .shoulderBelowToe: "shoulder exposure"
        case .negativeCurveFalls: "green layer's negative curve"
        case .printingDensityDiagonalNotPositive: "diagonal"
        case .printingDensitySingular: "determinant"
        case .printingDensityGammaNotPositive: "rise with neutral exposure"
        case .zeroPrintRange: "density range"
        case .zeroPrintShape: "shape"
        case .negativeMinimumDensity: "minimum density"
        case .middleGrayOutOfRange: "middle gray"
        case .retentionOutOfRange: "retention"
        case .sensitivityRowNotOne: "sensitivity"
        case .dyeRowNotOne: "dye"
        case .calibrationCannotConverge: "printer lights"
        }
    }
}

enum InvalidStockFile: CaseIterable, CustomTestStringConvertible {
    case unsupportedFormatVersion, shortGamma, twoMatrixRows, longMatrixRow, missingKey

    var testDescription: String { "\(self)" }

    /// Edits the decoded JSON tree, so the cases don't depend on the encoder's layout.
    func edit(_ data: Data) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var negative = try #require(json["negative"] as? [String: Any])
        var print = try #require(json["print"] as? [String: Any])
        switch self {
        case .unsupportedFormatVersion: json["formatVersion"] = FilmStock.supportedFormatVersion + 1
        case .shortGamma: negative["gamma"] = (negative["gamma"] as? [Double]).map { Array($0.prefix(2)) }
        case .twoMatrixRows: negative["sensitivity"] = (negative["sensitivity"] as? [[Double]]).map { Array($0.dropFirst()) }
        case .longMatrixRow:
            negative["printingDensity"] = (negative["printingDensity"] as? [[Double]]).map { [$0[0] + [0]] + $0.dropFirst() }
        case .missingKey: print["minimumDensity"] = nil
        }
        json["negative"] = negative
        json["print"] = print
        return try JSONSerialization.data(withJSONObject: json)
    }
}

extension FilmStock {
    /// The bundled default stock file. Throws rather than traps, so a broken file fails the tests that read it.
    static func bundledDefault() throws(EmulsionError) -> FilmStock { try .bundled(named: "emulsion-default") }
}
