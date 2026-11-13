import Foundation
import Testing

@testable import EmulsionFit

/// Synthetic dye sets and responsivities built here; no external data.
struct DyeSetTests {
    static let grid = Array(stride(from: 400.0, through: 700, by: 5))

    static func gaussian(peak: Double, width: Double) -> [Double] {
        grid.map { exp(-0.5 * pow(($0 - peak) / width, 2)) }
    }

    /// Cyan, magenta and yellow bands with some unwanted absorption, on a sloping base.
    static let dyeSet = NegativeDyeSet(
        wavelengths: grid, minimumDensity: grid.map { 0.2 + 0.6 * (700 - $0) / 300 },
        dyes: [
            zip(gaussian(peak: 660, width: 45), gaussian(peak: 520, width: 60)).map { $0 + 0.1 * $1 },
            zip(gaussian(peak: 545, width: 35), gaussian(peak: 440, width: 25)).map { $0 + 0.15 * $1 },
            gaussian(peak: 450, width: 30),
        ])

    static func responsivities(_ peaks: [Double], width: Double) -> SpectralResponsivities {
        SpectralResponsivities(name: "test", wavelengths: grid, channels: peaks.map { gaussian(peak: $0, width: width) })
    }

    static let statusMLike = responsivities([640, 540, 450], width: 20)
    static let printingLike = responsivities([670, 530, 430], width: 15)

    /// One weight at one wavelength per channel: integral density is then that wavelength's spectral density.
    static func narrowBand(_ wavelengths: [Double]) -> SpectralResponsivities {
        SpectralResponsivities(
            name: "narrow", wavelengths: grid, channels: wavelengths.map { peak in grid.map { $0 == peak ? 1 : 0 } })
    }

    @Test func spectrallyFlatDensityReadsTheSameInAnyResponsivity() {
        let flat = [Double](repeating: 0.7, count: Self.grid.count)
        for responsivities in [Self.statusMLike, Self.printingLike, Self.narrowBand([600, 500, 420])] {
            #expect(responsivities.densities(of: flat).allSatisfy { abs($0 - 0.7) < 1e-12 })
        }
    }

    @Test func narrowBandDensitiesMakeTheLinearFitsExact() throws {
        let statusM = Self.dyeSet.densitometer(Self.narrowBand([640, 540, 450]))
        let printing = Self.dyeSet.densitometer(Self.narrowBand([660, 530, 440]))
        func point(_ amounts: [Double]) -> PrintingDensityConversion.Point {
            .init(dyeAmounts: amounts, statusM: statusM, printingDensity: printing)
        }
        let neutral = (0...10).map { step in [0.9, 1.0, 1.1].map { $0 * Double(step) / 5 } }.map(point)
        let lattice = PrintingDensityConversion.lattice(maxAmounts: [2, 2, 2]).map(point)
        for model in PrintingDensityConversion.Model.allCases {
            let fit = try PrintingDensityConversion.fit(model, neutralScale: neutral, lattice: lattice)
            #expect((fit.neutralScale.maxAbs + fit.lattice.maxAbs).allSatisfy { $0 < 1e-9 }, "\(model)")
        }
        let dyes = try PrintingDensityConversion.fit(.dyeAmounts, neutralScale: neutral, lattice: lattice)
        let expected = [660.0, 530, 440].map { wavelength in
            Self.dyeSet.dyes.map { $0[Self.grid.firstIndex(of: wavelength) ?? 0] }
        }
        #expect(zip(dyes.matrix.flatMap { $0 }, expected.flatMap { $0 }).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    /// Broadband responsivities make the conversion nonlinear, so weighting the neutral scale trades lattice error for
    /// neutral-scale error; residuals stay unweighted, so weight 1 is the plain fit.
    @Test func neutralScaleWeightTradesLatticeErrorForNeutralError() throws {
        let (statusM, printing) = (Self.dyeSet.densitometer(Self.statusMLike), Self.dyeSet.densitometer(Self.printingLike))
        func point(_ amounts: [Double]) -> PrintingDensityConversion.Point {
            .init(dyeAmounts: amounts, statusM: statusM, printingDensity: printing)
        }
        let neutral = (0...20).map { step in [0.9, 1.0, 1.1].map { $0 * Double(step) / 10 } }.map(point)
        let lattice = PrintingDensityConversion.lattice(maxAmounts: [2, 2, 2]).map(point)
        let plain = try PrintingDensityConversion.fit(.dyeAmountsWithOffset, neutralScale: neutral, lattice: lattice)
        let unit = try PrintingDensityConversion.fit(.dyeAmountsWithOffset, neutralScaleWeight: 1, neutralScale: neutral, lattice: lattice)
        #expect(unit == plain)
        let engine = try #require(
            NegativeDyeSetReport.ConversionSet.fitting(printingDensity: "test", neutralScale: neutral, lattice: lattice).engine)
        #expect(engine.neutralScaleWeight == PrintingDensityConversion.engineNeutralScaleWeight)
        #expect(engine.neutralScale.rms.reduce(0, +) < plain.neutralScale.rms.reduce(0, +))
        #expect(engine.lattice.rms.reduce(0, +) > plain.lattice.rms.reduce(0, +))
        let offset = try #require(engine.offset)
        let residuals = neutral.map { sample in
            (0..<3).map { c in sample.printingDensity[c] - engine.matrix[c].dot(sample.dyeAmounts) - offset[c] }
        }
        for c in 0..<3 { #expect(abs(residuals.map { $0[c] }.rms - engine.neutralScale.rms[c]) < 1e-12) }
    }

    @Test(arguments: [[0.8, 1.1, 0.5], [0.0, 0.0, 0.0], [2.0, 0.3, 1.7]])
    func newtonRecoversKnownDyeAmounts(_ amounts: [Double]) throws {
        let statusM = Self.dyeSet.densitometer(Self.statusMLike)
        let solved = try statusM.amounts(forDensityAboveMinimum: statusM.densityAboveMinimum(amounts), from: [0, 0, 0])
        #expect(zip(solved, amounts).allSatisfy { abs($0 - $1) < 1e-8 })
    }

    @Test func unreachableDensityThrows() {
        // Every channel is bounded by the dye set; a narrow band with no dye absorption can't reach any density.
        let blind = SpectralResponsivities(
            name: "blind", wavelengths: Self.grid, channels: Array(repeating: Self.grid.map { $0 == 400 ? 1 : 0 }, count: 3))
        #expect(throws: DyeSetError.self) {
            try Self.dyeSet.densitometer(blind).amounts(forDensityAboveMinimum: [1, 0.5, 0.2], from: [0, 0, 0])
        }
    }

    @Test func jacobianMatchesFiniteDifferences() {
        let amounts = [0.7, 1.2, 0.9]
        let step = 1e-6
        let printing = Self.dyeSet.densitometer(Self.printingLike)
        let analytic = printing.jacobian(amounts)
        for k in 0..<3 {
            var high = amounts
            var low = amounts
            high[k] += step
            low[k] -= step
            let difference = zip(printing.densityAboveMinimum(high), printing.densityAboveMinimum(low)).map { ($0 - $1) / (2 * step) }
            for channel in 0..<3 { #expect(abs(analytic[channel][k] - difference[channel]) < 1e-7) }
        }
    }

    @Test func statusMInterpolatesAndExtrapolatesInLog10() throws {
        let csv = "wavelength_nm,blue,green,red\n400,4,,\n410,5,,\n420,,5,3\n430,,4,5\n"
        let slopes = """
            {"blue": {"below": 0.25, "above": -0.2}, "green": {"below": 0.1, "above": -0.1},
             "red": {"below": 0.3, "above": -0.05}}
            """
        let statusM = try StandardsTables.statusM(csv: csv, slopesJSON: slopes, file: "t.csv", grid: [390, 405, 420, 425, 440])
        let blue = statusM.channels[2]
        #expect(abs(blue[0] - pow(10, 4 - 2.5 - 5)) < 1e-15)
        #expect(abs(blue[1] - pow(10, 4.5 - 5)) < 1e-12)
        #expect(abs(blue[2] - pow(10, 5 - 2 - 5)) < 1e-12)
        let red = statusM.channels[0]
        #expect(abs(red[3] - pow(10, 4 - 5)) < 1e-12)
        #expect(abs(red[4] - pow(10, 5 - 0.5 - 5)) < 1e-12)
        #expect(abs(statusM.channels[1][2] - 1) < 1e-12)
    }

    @Test func printingDensityTablesInterpolateLinearlyAndAreZeroOutside() throws {
        let academy = try StandardsTables.academyPrintingDensity(
            csv: "Title,,,\n,,,\nWavelength,Pi_APD,Pi_APD,Pi_APD\n nm,Red,Green,Blue\n400,0,0,1\n410,1,0.5,0\n",
            file: "a.csv", grid: [395, 400, 405, 410, 415])
        #expect(academy.channels == [[0, 0, 0.5, 1, 0], [0, 0, 0.25, 0.5, 0], [0, 1, 0.5, 0, 0]])
        #expect(throws: FitError.self) {
            try StandardsTables.academyPrintingDensity(csv: "nm,R,G,B\n400,0,0,1\n", file: "a.csv", grid: [400])
        }
    }

    @Test func standardsDirectoryResolvesFlagThenEnvironmentThenSiblingOfTheReferenceData() {
        let data = URL(filePath: "/research/datasheet-tracings", directoryHint: .isDirectory)
        let flag = URL(filePath: "/flag", directoryHint: .isDirectory)
        let resolve = StandardsTables.directory(flag:environment:referenceData:)
        #expect(resolve(flag, "/env", data) == flag)
        #expect(resolve(nil, "/env", data).path == "/env")
        #expect(resolve(nil, "", data).path == "/research/standards")
        #expect(resolve(nil, nil, data).path == "/research/standards")
    }

    @Test func dyesNeedsTheReferenceDataThenTheStandardsTables() throws {
        let options = FitCommand.DyesOptions(
            stock: "kodak-vision3-250d-5207", out: URL(filePath: "/tmp/unused", directoryHint: .isDirectory))
        let home = FitCommandTests.home
        #expect(throws: CommandLineError.noReferenceData(FitCommandTests.missingData)) {
            try FitTool.perform(.dyes(options), environment: FitCommandTests.missingData, standardsEnvironment: nil, home: home)
        }
        let data = FileManager.default.temporaryDirectory.appending(
            path: "emulsion-tracings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: data) }
        let sibling = data.deletingLastPathComponent().appending(path: StandardsTables.siblingFolderName, directoryHint: .isDirectory)
        try #require(!sibling.isExistingDirectory)
        #expect(throws: CommandLineError.noStandardsDirectory(sibling.path)) {
            try FitTool.perform(.dyes(options), environment: data.path, standardsEnvironment: nil, home: home)
        }
    }

    @Test func standardsTablesMustMatchTheManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "emulsion-standards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = StandardsManifest(
            formatVersion: 1,
            files: StandardsTables.files.map { .init(file: $0, standard: "", edition: "", table: "", source: "", sha256: "00") })
        #expect(throws: FitError.missingFile(directory.appending(path: StandardsTables.statusMFile).path)) {
            try StandardsTables.load(from: directory, manifest: manifest)
        }
        let contents = Data("wavelength_nm,blue,green,red\n".utf8)
        for file in StandardsTables.files { try contents.write(to: directory.appending(path: file)) }
        #expect(
            throws: FitError.checksumMismatch(
                file: directory.appending(path: StandardsTables.statusMFile).path, expected: "00",
                found: DigitizedChart.sha256(of: contents))
        ) {
            try StandardsTables.load(from: directory, manifest: manifest)
        }
    }

    @Test func bundledManifestListsEveryStandardsTable() throws {
        let manifest = try StandardsManifest.bundled()
        #expect(manifest.files.map(\.file).sorted() == StandardsTables.files.sorted())
        #expect(manifest.files.allSatisfy { $0.sha256.count == 64 && $0.source.hasPrefix("https://") })
    }

    @Test func latticeSpansTheBoxEvenly() {
        let lattice = PrintingDensityConversion.lattice(maxAmounts: [1, 2, 4])
        #expect(lattice.count == 729)
        #expect(lattice.first == [0, 0, 0] && lattice.last == [1, 2, 4])
        #expect(lattice[1] == [0, 0, 0.5])
    }

    @Test func dyeSumCheckKeepsOnlyTheWavelengthStep() throws {
        let chart = try StockDataTests.dyeChart(
            """
            wavelength_nm,yellow,magenta,cyan,midscale_neutral,minimum_density
            400,1,0,0,1.5,0.5
            405,0,1,0,9,0.4
            410,0,0,1,1.6,0.6
            """)
        let check = try #require(DyeSumCheck.compared(chart, .init(subtractsMinimumDensity: true, wavelengthStep: 10)))
        #expect(check.wavelengths == [400, 410])
        #expect(check.maxAbsResidual < 1e-12)
    }
}
