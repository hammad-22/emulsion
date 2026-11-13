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
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }

    private func render(_ scene: CIImage, _ a: Adjustments) throws -> CIImage {
        try renderer.render(Negative(image: scene, contract: .sceneReferred), a)
    }

    private static func adjustments(halation: Double, backing: AntihalationBacking = .remJet) -> Adjustments {
        var a = Adjustments.neutral
        (a.halation, a.backing) = (halation, backing)
        return a
    }

    @Test func writeRendersAndMeasurements() throws {
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["EMULSION_PROOF_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = 800
        let point = SceneFixtures.highlightPoint(size: size)
        let edge = SceneFixtures.edge()
        let off = Self.adjustments(halation: 0)

        let pointOff = try render(point, off)
        try EmulsionTestCase.writePNG(pointOff, to: directory.appending(path: "highlight-point-halation0.png"))
        for backing in [AntihalationBacking.remJet, .none] {
            let on = Self.adjustments(halation: 1, backing: backing)
            let pointOn = try render(point, on)
            try EmulsionTestCase.writePNG(pointOn, to: directory.appending(path: "highlight-point-halation1-\(backing).png"))
            try EmulsionTestCase.writePNG(try render(edge, on), to: directory.appending(path: "edge-halation1-\(backing).png"))
            for scene in RealScene.allCases {
                var look = Adjustments()
                (look.seed, look.backing) = (7, backing)
                try EmulsionTestCase.writePNG(
                    try render(try scene.image(), look), to: directory.appending(path: "\(scene.rawValue)-default-look-\(backing).png"))
            }
            let delta = zip(EmulsionTestCase.codes(pointOn), EmulsionTestCase.codes(pointOff)).map { $0 - $1 }
            try Self.ringMeans(delta, size: size, header: "radius_px,radius_frame,dR_codes,dG_codes,dB_codes")
                .write(to: directory.appending(path: "radial-display-delta-\(backing).csv"), atomically: true, encoding: .utf8)
        }
        let on = Self.adjustments(halation: 1, backing: .none)

        // Red vs blue source of equal luminance (P3 primaries): red display-code glow at the same offsets.
        let radius: Float = 12
        let red = SIMD3<Float>(16, 0, 0)
        let blue = SIMD3<Float>(0, 0, 16 * 0.2289746 / 0.0792869)
        func redGlow(_ light: SIMD3<Float>) throws -> [SIMD3<Double>] {
            let disc = SceneFixtures.disc(size: size, radius: radius, light: light)
            return zip(EmulsionTestCase.codes(try render(disc, on)), EmulsionTestCase.codes(try render(disc, off))).map { $0 - $1 }
        }
        let fromRed = try redGlow(red)
        let fromBlue = try redGlow(blue)
        var ratio = ["offset_px,dR_red_source,dR_blue_source,blue_over_red"]
        for offset in stride(from: 14, through: 80, by: 2) {
            let i = EmulsionTestCase.pixel(x: size / 2 + offset, y: size / 2, width: size)
            ratio.append(String(format: "%d,%.4f,%.4f,%.4f", offset, fromRed[i].x, fromBlue[i].x, fromBlue[i].x / max(fromRed[i].x, 1e-9)))
        }
        try ratio.joined(separator: "\n").write(to: directory.appending(path: "red-vs-blue-display.csv"), atomically: true, encoding: .utf8)

        // Added red-layer exposure around HalationDisc (unbacked, amount 1), ring means, beside the
        // mixture and the exact derived profile, each convolved with the disc.
        let k = Halation.layerReturn(amount: 1, backing: .none).x
        let share = k / (1 + k)
        let exact = try HalationReference.load().irradianceProfile()
        func exactKernel(_ r: Double) -> Double {
            guard let upper = exact.rT.firstIndex(where: { $0 >= r }) else { return 0 }
            guard upper > 0 else { return exact.hT2[0] }
            let t = (r - exact.rT[upper - 1]) / (exact.rT[upper] - exact.rT[upper - 1])
            return exact.hT2[upper - 1] + t * (exact.hT2[upper] - exact.hT2[upper - 1])
        }
        let disc = HalationDisc(size: size)
        let withHalation = try renderer.sceneWithHalation(disc.scene, on)
        let sensitivity = FilmLook.stock.sensitivity
        let added = zip(
            Fixtures.encodedFloats(withHalation, space: SceneFixtures.linearP3),
            Fixtures.encodedFloats(disc.scene, space: SceneFixtures.linearP3)
        ).map { sensitivity * ($0 - $1) }
        let perBase = Halation.pixelsPerBaseThickness(longEdge: Double(size))
        var layer = ["radius_px,radius_t,radius_frame,dE_red_measured,dE_red_mixture,dE_red_exact"]
        let rings = Self.ringMeans(added, size: size, header: "").split(separator: "\n").dropFirst()
        for line in rings.prefix(120) {
            let fields = line.split(separator: ",")
            guard let r = Int(fields[0]), let measured = Double(fields[2]) else { continue }
            let point = SIMD2(Double(size / 2 + r), Double(size / 2))
            let own = Float(r) < disc.radius ? disc.redExposure : disc.backgroundRedExposure
            let mixture = share * (disc.redExposure(glowAt: point) - own)
            let derived = share * (disc.redExposure(glowAt: point, kernel: exactKernel) - own)
            layer.append(
                String(format: "%d,%.4f,%.5f,%.6f,%.6f,%.6f", r, Double(r) / perBase, Double(r) / Double(size), measured, mixture, derived))
        }
        try layer.joined(separator: "\n").write(
            to: directory.appending(path: "radial-red-layer-exposure.csv"), atomically: true, encoding: .utf8)

        let redLayer = try addedRedLayer(SceneFixtures.disc(size: size, radius: radius, light: red), on)
        let blueLayer = try addedRedLayer(SceneFixtures.disc(size: size, radius: radius, light: blue), on)
        var layerRatio = ["offset_px,dE_red_red_source,dE_red_blue_source,blue_over_red"]
        for offset in stride(from: 14, through: 80, by: 2) {
            let i = EmulsionTestCase.pixel(x: size / 2 + offset, y: size / 2, width: size)
            layerRatio.append(
                String(format: "%d,%.6f,%.6f,%.4f", offset, redLayer[i], blueLayer[i], blueLayer[i] / max(redLayer[i], 1e-12)))
        }
        try layerRatio.joined(separator: "\n").write(
            to: directory.appending(path: "red-vs-blue-layer.csv"), atomically: true, encoding: .utf8)
    }

    private func addedRedLayer(_ scene: CIImage, _ a: Adjustments) throws -> [Double] {
        let sensitivity = FilmLook.stock.sensitivity
        return zip(
            Fixtures.encodedFloats(try renderer.sceneWithHalation(scene, a), space: SceneFixtures.linearP3),
            Fixtures.encodedFloats(scene, space: SceneFixtures.linearP3)
        ).map { (sensitivity * ($0 - $1)).x }
    }

    /// Means of `values` over rings 1 px wide around the frame centre, as CSV rows (r, r/size, x, y, z).
    private static func ringMeans(_ values: [SIMD3<Double>], size: Int, header: String) -> String {
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
        var rows = [header]
        for r in 0..<size / 2 where counts[r] > 0 {
            let m = sums[r] / counts[r]
            rows.append(String(format: "%d,%.5f,%.6f,%.6f,%.6f", r, Double(r) / Double(size), m.x, m.y, m.z))
        }
        return rows.joined(separator: "\n")
    }
}
