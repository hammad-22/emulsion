import CoreImage
import EmulsionFixtures
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import EmulsionCore

/// Before/after evidence for display-referred sources (JPEG/HEIC): writes PNG renders of the
/// proof chart and prints a table of numbers. Opt-in: EMULSION_PROOF=<output directory>.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMULSION_PROOF"] != nil))
struct DisplayReferredProof {
    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }

    @Test func writeRendersAndNumbers() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["EMULSION_PROOF"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let chart = DisplayFixtures.proofChart()
        let negative = try renderer.materialize(try renderer.developer.sceneFromDisplay(chart))
        let width = DisplayFixtures.chartWidth

        func rendered(exposure: Double) throws -> CIImage {
            var a = Adjustments.neutral
            a.exposure = exposure
            return try renderer.render(negative, a)
        }
        let zero = try rendered(exposure: 0)
        let down3 = try rendered(exposure: -3)
        let up2 = try rendered(exposure: 2)
        for (name, image) in [("source", chart), ("zero-edits", zero), ("minus-3ev", down3), ("plus-2ev", up2)] {
            try writePNG(image, to: directory.appendingPathComponent("\(name).png"))
        }

        var lines = ["Display-referred proof (chart \(width) px wide; codes are encoded Display P3 x255, before 8-bit rounding)"]
        let zeroCodes = EmulsionTestCase.codes(zero)
        let grayRow = EmulsionTestCase.pixel(x: 0, y: DisplayFixtures.grayRow, width: width)
        var errors = [Double]()
        for code in 0..<256 { for c in 0..<3 { errors.append(abs(zeroCodes[grayRow + code][c] - Double(code))) } }
        lines.append(
            String(
                format: "gray round trip, zero edits, 256 codes x 3 channels: max error %.3f codes, mean %.3f",
                errors.max() ?? 0, errors.reduce(0, +) / Double(errors.count)))
        let ends = [0, 1, 2, 3, 4, 250, 251, 252, 253, 254, 255].map {
            String(format: "%d→%.1f", $0, zeroCodes[grayRow + $0].y)
        }
        lines.append("gray ends at zero edits (green): " + ends.joined(separator: " "))

        for (label, image) in [("-3 EV", down3), ("+2 EV", up2)] {
            let green = EmulsionTestCase.codes(image)[grayRow..<grayRow + 256].map(\.y)
            let steps = zip(green.dropFirst(), green).map { $0 - $1 }
            let maxStep = steps.max() ?? 0
            let at = steps.firstIndex(of: maxStep) ?? 0
            let top = green[248...].map { String(format: "%.1f", $0) }.joined(separator: " ")
            lines.append(
                String(
                    format: "%@ gray: max step %.2f codes (at %d→%d), min step %.3f; codes 248…255 → %@", label, maxStep, at, at + 1,
                    steps.min() ?? 0, top))
        }

        let skyRow = EmulsionTestCase.pixel(x: 0, y: DisplayFixtures.skyRow, width: width)
        for (label, image) in [("zero edits", zero), ("-3 EV", down3)] {
            let lab = Fixtures.oklab(image)
            let steps = (1..<width).map { Fixtures.deltaE(lab[skyRow + $0], lab[skyRow + $0 - 1]) }
            lines.append(String(format: "sky gradient %@: max adjacent OKLab ΔE×100 %.2f", label, steps.max() ?? 0))
        }

        lines.append("patch          ΔL       Δhue°   chroma ratio  ΔE×100   (zero edits, OKLab)")
        let sourceLab = Fixtures.oklab(chart)
        let outLab = Fixtures.oklab(zero)
        for (i, patch) in DisplayFixtures.patches.enumerated() {
            let (x, y) = DisplayFixtures.patchCenter(i)
            let i = EmulsionTestCase.pixel(x: x, y: y, width: width)
            let a = sourceLab[i]
            let b = outLab[i]
            lines.append(
                String(
                    format: "%@ %+.4f  %6.2f   %.3f         %.2f", patch.name.padding(toLength: 13, withPad: " ", startingAt: 0), b.x - a.x,
                    Fixtures.hueDifference(a, b), Fixtures.chroma(b) / max(Fixtures.chroma(a), 1e-9), Fixtures.deltaE(a, b)))
        }

        let scene = Fixtures.encodedFloats(negative.image, space: SceneFixtures.linearP3)
        let sceneMax = scene.map { $0.max() }.max() ?? 0
        let white = scene[grayRow + 255]
        let black = scene[grayRow]
        lines.append(
            String(format: "scene estimate (linear P3): max %.4g; display white → (%.4g, %.4g, %.4g)", sceneMax, white.x, white.y, white.z))
        lines.append(String(format: "scene estimate of display black → (%.4g, %.4g, %.4g)", black.x, black.y, black.z))
        for (i, patch) in DisplayFixtures.patches.prefix(9).enumerated() {
            let (x, y) = DisplayFixtures.patchCenter(i)
            let s = scene[EmulsionTestCase.pixel(x: x, y: y, width: width)]
            lines.append(String(format: "scene estimate %@ → (%.4g, %.4g, %.4g)", patch.name, s.x, s.y, s.z))
        }

        let table = lines.joined(separator: "\n")
        print(table)
        try table.write(to: directory.appendingPathComponent("numbers.txt"), atomically: true, encoding: .utf8)
    }

    private func writePNG(_ image: CIImage, to url: URL) throws {
        let cg = try renderer.cgImage(image)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
