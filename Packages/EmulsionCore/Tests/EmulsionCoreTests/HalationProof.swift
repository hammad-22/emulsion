import CoreImage
import EmulsionFixtures
import Foundation
import Testing
import simd

@testable import EmulsionCore

/// Before/after evidence for halation (MOV-32, MOV-102): PNG renders and CSV measurements.
/// Opt-in: EMULSION_PROOF_DIR=<output directory>.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"] != nil))
struct HalationProof {
    private static func write(_ rows: [String], _ url: URL) throws {
        try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func writeRendersAndMeasurements() throws {
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = 800
        let point = SceneFixtures.highlightPoint(size: size)
        let edge = SceneFixtures.edge()
        let off = HalationTests.adjustments(0, .remJet)

        let pointOff = try EmulsionTestCase.render(point, off)
        try EmulsionTestCase.writePNG(pointOff, to: directory.appending(path: "highlight-point-halation0.png"))
        for backing in [AntihalationBacking.remJet, .none] {
            let on = HalationTests.adjustments(1, backing)
            let pointOn = try EmulsionTestCase.render(point, on)
            try EmulsionTestCase.writePNG(pointOn, to: directory.appending(path: "highlight-point-halation1-\(backing).png"))
            try EmulsionTestCase.writePNG(
                try EmulsionTestCase.render(edge, on), to: directory.appending(path: "edge-halation1-\(backing).png"))
            for scene in RealScene.allCases {
                var look = Adjustments()
                (look.seed, look.backing) = (7, backing)
                try EmulsionTestCase.writePNG(
                    try EmulsionTestCase.render(try scene.image(), look),
                    to: directory.appending(path: "\(scene.rawValue)-default-look-\(backing).png"))
            }
            let delta = zip(EmulsionTestCase.codes(pointOn), EmulsionTestCase.codes(pointOff)).map { $0 - $1 }
            try Self.write(
                ["radius_px,radius_frame,dR_codes,dG_codes,dB_codes"]
                    + Self.ringMeans(delta, size: size).map {
                        String(
                            format: "%d,%.5f,%.6f,%.6f,%.6f", $0.radius, Double($0.radius) / Double(size), $0.mean.x, $0.mean.y, $0.mean.z)
                    }, directory.appending(path: "radial-display-delta-\(backing).csv"))
        }
        let on = HalationTests.adjustments()

        // Red vs blue source of equal luminance (P3 primaries): red display-code glow at the same offsets.
        let radius: Float = 12
        let (red, blue) = HalationTests.equalLuminanceRedAndBlue(red: 16)
        func redGlow(_ light: SIMD3<Float>) throws -> [SIMD3<Double>] {
            let disc = SceneFixtures.disc(size: size, radius: radius, light: light)
            return zip(
                EmulsionTestCase.codes(try EmulsionTestCase.render(disc, on)),
                EmulsionTestCase.codes(try EmulsionTestCase.render(disc, off))
            )
            .map { $0 - $1 }
        }
        let fromRed = try redGlow(red)
        let fromBlue = try redGlow(blue)
        var ratio = ["offset_px,dR_red_source,dR_blue_source,blue_over_red"]
        for offset in stride(from: 14, through: 80, by: 2) {
            let i = EmulsionTestCase.pixel(x: size / 2 + offset, y: size / 2, width: size)
            ratio.append(String(format: "%d,%.4f,%.4f,%.4f", offset, fromRed[i].x, fromBlue[i].x, fromBlue[i].x / max(fromRed[i].x, 1e-9)))
        }
        try Self.write(ratio, directory.appending(path: "red-vs-blue-display.csv"))

        // Added red-layer exposure around HalationDisc (unbacked, amount 1), ring means, beside the
        // mixture and the exact derived profile, each convolved with the disc.
        let share = HalationTests.share().x
        let exact = try ColorReferences.halationKernel().irradianceProfile()
        func exactKernel(_ r: Double) -> Double {
            guard let upper = exact.rT.firstIndex(where: { $0 >= r }) else { return 0 }
            guard upper > 0 else { return exact.hT2[0] }
            let t = (r - exact.rT[upper - 1]) / (exact.rT[upper] - exact.rT[upper - 1])
            return exact.hT2[upper - 1] + t * (exact.hT2[upper] - exact.hT2[upper - 1])
        }
        let disc = HalationDisc(size: size)
        let added = try HalationTests.addedExposure(disc.scene, on)
        let perBase = Halation.pixelsPerBaseThickness(longEdge: Double(size))
        let (light, background) = (disc.discExposure().x, disc.backgroundExposure)
        var layer = ["radius_px,radius_t,radius_frame,dE_red_measured,dE_red_mixture,dE_red_exact"]
        for ring in Self.ringMeans(added, size: size).prefix(120) {
            let r = ring.radius
            let at = SIMD2(Double(size / 2 + r), Double(size / 2))
            let own = Float(r) < disc.radius ? light : background
            let mixture = share * (background + (light - background) * disc.discShare(at: at) - own)
            let derived = share * (background + (light - background) * disc.discShare(at: at, kernel: exactKernel) - own)
            layer.append(
                String(
                    format: "%d,%.4f,%.5f,%.6f,%.6f,%.6f", r, Double(r) / perBase, Double(r) / Double(size), ring.mean.x, mixture, derived))
        }
        try Self.write(layer, directory.appending(path: "radial-red-layer-exposure.csv"))

        let redLayer = try HalationTests.addedExposure(SceneFixtures.disc(size: size, radius: radius, light: red), on).map(\.x)
        let blueLayer = try HalationTests.addedExposure(SceneFixtures.disc(size: size, radius: radius, light: blue), on).map(\.x)
        var layerRatio = ["offset_px,dE_red_red_source,dE_red_blue_source,blue_over_red"]
        for offset in stride(from: 14, through: 80, by: 2) {
            let i = EmulsionTestCase.pixel(x: size / 2 + offset, y: size / 2, width: size)
            layerRatio.append(
                String(format: "%d,%.6f,%.6f,%.4f", offset, redLayer[i], blueLayer[i], blueLayer[i] / max(redLayer[i], 1e-12)))
        }
        try Self.write(layerRatio, directory.appending(path: "red-vs-blue-layer.csv"))
    }

    /// Means of `values` over rings 1 px wide around the frame centre, by radius in pixels.
    private static func ringMeans(_ values: [SIMD3<Double>], size: Int) -> [(radius: Int, mean: SIMD3<Double>)] {
        var sums = [SIMD3<Double>](repeating: .zero, count: size / 2)
        var counts = [Double](repeating: 0, count: size / 2)
        for y in 0..<size {
            for x in 0..<size {
                let r = Int(hypot(Double(x - size / 2), Double(y - size / 2)).rounded())
                guard r < size / 2 else { continue }
                sums[r] += values[EmulsionTestCase.pixel(x: x, y: y, width: size)]
                counts[r] += 1
            }
        }
        return (0..<size / 2).filter { counts[$0] > 0 }.map { ($0, sums[$0] / counts[$0]) }
    }
}
