// Generates the synthetic sample photos bundled with EmulsionKit, so the app has something
// to develop on an empty library. Generated, not photographed: no license questions.
// Usage: swift Tools/make-sample-photos.swift
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Packages/EmulsionKit/Sources/EmulsionKit/Resources/Samples")
let frame = CGRect(x: 0, y: 0, width: 1800, height: 1200)
let context = CIContext()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CIColor { CIColor(red: r, green: g, blue: b, alpha: a) }
func solid(_ c: CIColor, _ rect: CGRect = frame) -> CIImage { CIImage(color: c).cropped(to: rect) }
func glow(at center: CGPoint, core: Double, falloff: Double, _ inner: CIColor, _ outer: CIColor) -> CIImage {
    let filter = CIFilter.radialGradient()
    filter.center = center
    filter.radius0 = Float(core)
    filter.radius1 = Float(falloff)
    filter.color0 = inner
    filter.color1 = outer
    return filter.outputImage!
}
func save(_ image: CIImage, _ name: String) throws {
    try context.writeJPEGRepresentation(
        of: image.cropped(to: frame), to: output.appendingPathComponent(name), colorSpace: sRGB,
        options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.85])
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Dusk: a warm sky gradient, a bright low sun, dark ground. Tests highlights and warmth.
let sky = CIFilter.linearGradient()
sky.point0 = CGPoint(x: 0, y: 1200)
sky.point1 = CGPoint(x: 0, y: 380)
sky.color0 = color(0.15, 0.25, 0.55)
sky.color1 = color(1.0, 0.55, 0.25)
let sun = glow(at: CGPoint(x: 1130, y: 480), core: 45, falloff: 200, color(1, 0.98, 0.9), color(1, 0.6, 0.3, 0))
try save(
    solid(color(0.08, 0.1, 0.08), CGRect(x: 0, y: 0, width: 1800, height: 390)).composited(over: sun.composited(over: sky.outputImage!)),
    "Dusk.jpg")

// Color chart: twelve saturated and neutral patches on mid gray. Tests color and tint.
let patches: [CIColor] = [
    color(0.8, 0.2, 0.2), color(0.9, 0.6, 0.1), color(0.9, 0.85, 0.2), color(0.3, 0.7, 0.3),
    color(0.2, 0.6, 0.8), color(0.25, 0.3, 0.8), color(0.6, 0.3, 0.7), color(0.85, 0.65, 0.55),
    color(0.95, 0.95, 0.95), color(0.05, 0.05, 0.05), color(0.55, 0.35, 0.25), color(0.4, 0.5, 0.25),
]
var chart = solid(color(0.45, 0.45, 0.45))
for (i, patch) in patches.enumerated() {
    let cell = CGRect(x: 150 + CGFloat(i % 4) * 390, y: 150 + CGFloat(i / 4) * 315, width: 330, height: 255)
    chart = solid(patch, cell).composited(over: chart)
}
try save(chart, "Color Chart.jpg")

// Street lights: small bright lamps on a dark blue night. Tests halation and grain.
var night = solid(color(0.03, 0.05, 0.1))
for i in 0..<7 {
    let lamp = CGPoint(x: 190 + Double(i) * 240, y: 680 + Double(i % 2) * 135)
    night = glow(at: lamp, core: 14, falloff: 52, color(1, 0.95, 0.8), color(1, 0.7, 0.3, 0)).composited(over: night)
}
try save(night, "Street Lights.jpg")
print("Wrote samples to \(output.path)")
