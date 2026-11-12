import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Before/after evidence for grain (MOV-30): 100% crops, the frozen scenes, σ against exposure, the
/// display-luma spectrum, preview/export σ ratios and the density σ the table sets.
/// Opt-in: EMULSION_PROOF_DIR=<output directory>.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"] != nil))
struct GrainProof {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }
    private static let (width, height, side) = (4032, 3024, 1024)

    private static func adjustments(grain: Double, seed: Double = 3) -> Adjustments {
        var a = Adjustments.neutral
        (a.grain, a.seed) = (grain, seed)
        return a
    }

    private func render(_ scene: CIImage, _ a: Adjustments) throws -> CIImage {
        try renderer.render(Negative(image: scene, contract: .sceneReferred), a)
    }

    private static func write(_ rows: [String], _ url: URL) throws {
        try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func writeRendersAndMeasurements() throws {
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (w, h, side) = (Self.width, Self.height, Self.side)
        let square = CGRect(x: 0, y: 0, width: 256, height: 256)

        for stops in [-3.0, 0, 3] {
            for grain in [1.0, 0.35] {
                let image = try render(GrainMeasurement.flat(stops: stops, width: w, height: h), Self.adjustments(grain: grain))
                let name = String(format: "patch-%+.0fstops-grain%.2f-4032-crop256.png", stops, grain)
                try EmulsionTestCase.writePNG(image.cropped(to: square), to: directory.appending(path: name))
            }
        }
        for scene in RealScene.allCases {
            var look = Adjustments()
            look.seed = 7
            try EmulsionTestCase.writePNG(
                try render(try scene.image(), look), to: directory.appending(path: "\(scene.rawValue)-default-look.png"))
        }

        // Display σ (P3 codes ×255, before quantization) on a 1024² crop of the 4032×3024 render.
        var rows = ["stops,mean_luma,sd_luma,sd_R,sd_G,sd_B,mean_luma_no_grain"]
        for stops in stride(from: -6.0, through: 6, by: 1) {
            let scene = GrainMeasurement.flat(stops: stops, width: w, height: h)
            let grainy = GrainMeasurement.linearCrop(try render(scene, Self.adjustments(grain: 1)), size: side)
            let clean = GrainMeasurement.linearCrop(try render(scene, Self.adjustments(grain: 0)), size: 8)
            let sd = GrainMeasurement.channelSD(grainy)
            let luma = grainy.map { GrainMeasurement.luma(GrainMeasurement.codes($0)) }
            rows.append(
                String(
                    format: "%.0f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", stops, GrainMeasurement.mean(luma),
                    GrainMeasurement.standardDeviation(luma),
                    sd.x, sd.y, sd.z, GrainMeasurement.mean(clean.map { GrainMeasurement.luma(GrainMeasurement.codes($0)) })))
        }
        try Self.write(rows, directory.appending(path: "display-sd-vs-stops.csv"))

        // Radially averaged power spectrum of mid-gray display luma (codes²), 64-px tiles over 1024².
        let mid = GrainMeasurement.linearCrop(
            try render(GrainMeasurement.flat(stops: 0, width: w, height: h), Self.adjustments(grain: 1)), size: side)
        let spectrum = GrainMeasurement.radialPowerSpectrum(
            mid.map { GrainMeasurement.luma(GrainMeasurement.codes($0)) }, width: side, height: side)
        try Self.write(
            ["cycles_per_pixel,power_codes2"] + spectrum.map { String(format: "%.4f,%.5f", $0.frequency, $0.power) },
            directory.appending(path: "display-luma-spectrum.csv"))

        try Self.write(
            [
                "preview_long_edge,scale,sd_preview,sd_export,sd_area,sd_lanczos,ratio_area,ratio_area_white,ratio_lanczos,ratio_selwyn,scale2_mean_w2"
            ]
                + GrainMeasurement.previewExport(renderer).map {
                    String(
                        format: "%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", $0.previewLongEdge, $0.scale, $0.preview, $0.export,
                        $0.area, $0.lanczos, $0.areaRatio, $0.areaRatioWhite, $0.lanczosRatio, $0.selwynRatio, $0.areaWhiteVarianceFactor)
                }, directory.appending(path: "preview-export-ratios.csv"))

        try Self.write(try sigmaAgainstStops(), directory.appending(path: "density-and-display-sigma-vs-stops.csv"))
    }

    /// Per stop at 4032×3024, grain 1: the datasheet σ_D at 48 µm (the engine table and Kodak's
    /// trace read at even stops), the engine's per-pixel σ, the negative-density σ measured as σ·SD(n)
    /// on the noise field, and the display σ predicted by the mirror against the rendered one.
    private func sigmaAgainstStops() throws -> [String] {
        let (w, h, side) = (Self.width, Self.height, Self.side)
        let trace = try GrainReference.granularity().sigmaAtCameraStops
        let noise = Fixtures.linear(try renderer.grainNoise(CGRect(x: 0, y: 0, width: side, height: side), seed: 3))
        let noiseSD = SIMD3((0..<3).map { c in GrainMeasurement.standardDeviation(noise.map { $0[c] }) })
        var rows = [
            "stops,table48_R,table48_G,table48_B,trace48_R,trace48_G,trace48_B,pixel_R,pixel_G,pixel_B,"
                + "measured_neg_R,measured_neg_G,measured_neg_B,predicted_display_R,predicted_display_G,predicted_display_B,"
                + "rendered_display_R,rendered_display_G,rendered_display_B"
        ]
        for stops in stride(from: -6.0, through: 6, by: 1) {
            let logE = SIMD3(repeating: stops * log10(2.0))
            let table = Grain.sigmaD48(logExposure: logE)
            let pixel = Grain.densitySigma(logExposure: logE, amount: 1, longEdge: Double(w))
            let measured = pixel * noiseSD
            let key = String(format: "%.0f", stops)
            let traced = trace.map { $0[key].map { String(format: "%.5f", $0) } ?? "" }
            let predicted = GrainMeasurement.predictedDisplaySD(stops: stops, amount: 1, longEdge: Double(w))
            let rendered = GrainMeasurement.channelSD(
                GrainMeasurement.linearCrop(
                    try render(GrainMeasurement.flat(stops: stops, width: w, height: h), Self.adjustments(grain: 1)), size: 512))
            let numbers = [table, pixel, measured, predicted, rendered].flatMap { [$0.x, $0.y, $0.z] }
            rows.append(
                ([key] + numbers.prefix(3).map { String(format: "%.5f", $0) } + traced
                    + numbers.dropFirst(3).map { String(format: "%.5f", $0) })
                    .joined(separator: ","))
        }
        return rows
    }
}
