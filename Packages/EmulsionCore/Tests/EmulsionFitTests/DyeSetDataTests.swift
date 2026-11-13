import Foundation
import Testing

@testable import EmulsionFit

/// Runs only where the local reference data and standards tables are present (`EMULSION_REFERENCE_DATA` and
/// `EMULSION_STANDARDS_DIR`, else their defaults); CI skips them. Numbers are computed from the digitized datasheet,
/// not measured on film.
struct DyeSetDataTests {
    static let stock = "kodak-vision3-250d-5207"
    static let standardsDirectory = StandardsTables.defaultDirectory
    static let available =
        StockDataTests.referenceDataAvailable && standardsDirectory.isExistingDirectory && StockDataTests.presentStocks.contains(stock)

    /// Built once: the report takes seconds in a debug build.
    static let outcome = Result<NegativeDyeSetReport, any Error> {
        let standards = try StandardsTables.load(from: standardsDirectory)
        return try NegativeDyeSetReport.making(StockDataTests.load(stock), standards: standards, tool: "test")
    }

    static func report() throws -> NegativeDyeSetReport { try outcome.get() }

    @Test(.enabled(if: available))
    func midscaleNeutralIsReconstructed() throws {
        let midscale = try Self.report().midscale
        #expect(midscale.maxAbsResidual <= DyeSumCheck.targetMaxResidual)
        #expect(midscale.wavelengths.allSatisfy { NegativeDyeSetReport.midscaleWavelengths.contains($0) })
    }

    @Test(.enabled(if: available))
    func statusMOfMinimumDensityMatchesTheChartsLowestDensities() throws {
        let row = try #require(Self.report().mask.first)
        #expect(row.densityDefinition.hasPrefix("Status M"))
        #expect(row.difference.allSatisfy { abs($0) <= 0.04 })
    }

    @Test(.enabled(if: available))
    func statusMToAPDFollowsTheNeutralScale() throws {
        let report = try Self.report()
        let academy = report.academyConversions
        let neutralOnly = try #require(academy.fit(.statusM, fittedOn: .neutralScale))
        #expect(neutralOnly.neutralScale.maxAbs.allSatisfy { $0 <= 0.01 })
        // Fitted on colors too, the same 3×3 misses the neutral scale by up to about 0.02 D (green).
        let general = try #require(academy.fit(.statusM))
        #expect(general.neutralScale.maxAbs.allSatisfy { $0 <= 0.025 })
        // An offset lowers that to about 0.013 D.
        let withOffset = try #require(academy.fit(.statusMWithOffset))
        #expect(withOffset.neutralScale.maxAbs.allSatisfy { $0 <= 0.015 })
    }

    /// The engine's matrix follows the neutral scale within about 0.006 D and colors within RMS 0.025 D per channel;
    /// weighting the neutral scale ten times costs the lattice at most a few thousandths of RMS.
    @Test(.enabled(if: available))
    func engineMatrixFollowsTheNeutralScaleAndColors() throws {
        let report = try Self.report()
        let engine = try #require(report.academyEngineConversion)
        #expect(engine.model == .dyeAmountsWithOffset && engine.neutralScaleWeight == 10)
        #expect(engine.neutralScale.maxAbs.allSatisfy { $0 <= 0.007 })
        #expect(engine.lattice.rms.allSatisfy { $0 <= 0.025 })
        let unweighted = try #require(report.academyConversions.fit(.dyeAmountsWithOffset))
        #expect(zip(engine.lattice.rms, unweighted.lattice.rms).allSatisfy { $0 - $1 <= 0.005 })
        #expect(zip(engine.neutralScale.maxAbs, unweighted.neutralScale.maxAbs).allSatisfy { $0 <= $1 })
    }

    @Test(.enabled(if: available))
    func academyPrintingDensityGammasSitInTheExpectedRanges() throws {
        let label = NegativeDyeSetReport.Gammas.Quantity.academyPrintingDensity.label
        let row = try #require(Self.report().gammas.first { $0.quantity == label })
        let ranges: [ClosedRange<Double>] = [0.49...0.53, 0.55...0.60, 0.50...0.55]
        for (gamma, range) in zip(row.values, ranges) { #expect(gamma.map(range.contains) == true) }
    }

    @Test(.enabled(if: available))
    func dyesWritesByteIdenticalFilesOnEveryRun() throws {
        let runs = try (0..<2).map { _ in
            let out = FileManager.default.temporaryDirectory.appending(path: "emulsion-dyes-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            _ = try FitTool.perform(.dyes(.init(stock: Self.stock, out: out, standards: Self.standardsDirectory)))
            return try ["dye-set.json", "dye-set.md", "neutral-scale.csv"].map {
                try Data(contentsOf: out.appending(path: "\(Self.stock).\($0)"))
            }
        }
        #expect(runs[0] == runs[1])
    }
}
