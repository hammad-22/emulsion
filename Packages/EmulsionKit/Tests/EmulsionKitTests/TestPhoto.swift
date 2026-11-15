import CoreImage
import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

@testable import EmulsionKit

/// A small JPEG of the color-patch fixture.
enum TestPhoto {
    static let jpeg: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Encoded on the CPU so the tests' only GPU context is the shared renderer's (MOV-127).
        // A fixture that fails to encode is a broken test setup, not a test failure.
        return CIContext(options: [.useSoftwareRenderer: true])
            .jpegRepresentation(of: SceneFixtures.patches(), colorSpace: space)!
    }()

    /// A JPEG with fine detail (stripes over a gradient), where JPEG compression shows.
    static let detailedSize = (width: 640, height: 480)
    static let detailedJPEG: Data = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = Fixtures.image(width: detailedSize.width, height: detailedSize.height, space: space) { x, y in
            let stripe: Float = (x / 2 + y / 3).isMultiple(of: 2) ? 0.15 : 0
            return SIMD3(Float(x) / 640 * 0.7 + stripe, Float(y) / 480 * 0.7 + stripe, 0.4 + stripe)
        }
        return CIContext(options: [.useSoftwareRenderer: true]).jpegRepresentation(of: image, colorSpace: space)!
    }()

    /// A synthetic DNG (384 × 144) whose profile brightens through a gain table, as 48 MP ProRAW
    /// does, so its develop measures an exposure anchor (about 2 stops).
    static let anchoredRAW = RAWDevelopChart.dng(
        .bayerRGGB, chart: RAWDevelopChart.chart(), baselineStops: 0.5, profile: SyntheticDNG.Profile(gainTableGain: 4))
}

/// A throwaway library: its own folder and render service, removed when the test ends,
/// so tests can run in parallel.
@MainActor
final class TestLibrary {
    /// One renderer (GPU context and kernels) for every test's service, as the app has one.
    /// MOV-127: both CI crashes came as parallel tests each started their own context.
    /// `Renderer` holds only immutable state and a `CIContext`, which is thread-safe.
    /// Nil if the kernels fail to load; each service then reports that itself.
    static let renderer = try? Renderer()

    let folder = URL.temporaryDirectory.appending(path: "EmulsionKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    /// Where this library's services keep thumbnails on disk, as the app's Caches folder.
    let thumbnailsFolder = URL.temporaryDirectory.appending(
        path: "EmulsionKitTests-Thumbnails-\(UUID().uuidString)", directoryHint: .isDirectory)
    lazy var renderService = makeRenderService()
    lazy var store = PhotoStore(folder: folder, renderService: renderService)
    /// Settings in their own defaults suite, removed with the library.
    private let settingsSuite = "EmulsionKitTests-\(UUID().uuidString)"
    lazy var settingsDefaults = UserDefaults(suiteName: settingsSuite)!
    lazy var settings = AppSettings(defaults: settingsDefaults)

    /// The settings read again from the same suite, as on the next launch.
    func reopenedSettings() -> AppSettings { AppSettings(defaults: settingsDefaults) }

    /// The same folder opened again, as on the next launch.
    func reopened() -> PhotoStore {
        PhotoStore(folder: folder, renderService: makeRenderService())
    }

    /// A service as the app makes one, sharing this library's thumbnails on disk, as a relaunch does.
    func makeRenderService() -> RenderService {
        RenderService(
            renderer: TestLibrary.renderer,
            thumbnails: ThumbnailCache(purgesUnderMemoryPressure: false, files: ThumbnailFiles(parent: thumbnailsFolder)),
            latestRenders: LatestRenderCache(purgesUnderMemoryPressure: false))
    }

    /// A camera on the stand-in source with this library's store and settings.
    func camera(_ source: MockCameraSource = MockCameraSource()) -> CameraModel {
        CameraModel(source: source, store: store, settings: settings)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: thumbnailsFolder)
        UserDefaults().removePersistentDomain(forName: settingsSuite)
    }
}

/// 8-bit RGBA bytes of a rendered image (Display P3, as the renderer makes them), row by row.
enum TestPixels {
    static func rgba(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data as Data? else { return [] }
        return (0..<image.height).flatMap { row in data[(row * image.bytesPerRow)..<(row * image.bytesPerRow + image.width * 4)] }
    }

    /// `image` drawn into RGBA8 Display P3, so images decoded in different layouts compare byte for byte.
    static func redrawn(_ image: CGImage) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try #require(context.makeImage())
    }

    /// Max and mean absolute difference over the colour channels, in 8-bit codes.
    static func difference(_ a: CGImage, _ b: CGImage) -> (max: Int, mean: Double) {
        let (x, y) = (rgba(a), rgba(b))
        let diffs = x.indices.filter { $0 % 4 != 3 }.map { abs(Int(x[$0]) - Int(y[$0])) }
        return (diffs.max() ?? .max, Double(diffs.reduce(0, +)) / Double(max(diffs.count, 1)))
    }
}

/// Emulsion's curated looks by position: 0 Everyday (the default adjustments), 1 Warm Light,
/// 2 Quiet Color, 3 Night Glow.
enum TestLooks {
    static func curated(_ index: Int) throws -> Recipe {
        try #require(CuratedLooks.recipes.dropFirst(index).first)
    }
}

/// A synthetic DNG of a mid-gray and a red patch lit by CIE illuminant A (tungsten), which the
/// camera tagged as daylight (D65): as shot it develops with a strong cast.
enum TestRAW {
    static let chart = PatchChart([SIMD3(repeating: 0.18), SIMD3(0.4, 0.05, 0.03)])
    static let tungstenTaggedAsDaylight = RAWDevelopChart.dng(
        .linearRGB, chart: chart, light: SyntheticDNG.planckianChromaticity(kelvin: SyntheticDNG.illuminantAKelvin),
        taggedLight: SyntheticDNG.d65Chromaticity)
    /// The tagged light, D65, at its CCT (CIE 15:2004), and how far from it Apple reads the
    /// file's as-shot temperature: 6502 K measured, tolerance as in `CameraWhiteBalanceTests`.
    static let taggedKelvin = 6504.0
    static let asShotTemperatureTolerance = 15.0

    /// How far the gray patch's centre is from neutral: the largest difference between its
    /// channels, in 8-bit codes of a Display P3 image (as the renderer and its exports make them).
    static func grayCast(_ image: CGImage) throws -> Int {
        try #require(image.bitsPerPixel == 32 && image.bitsPerComponent == 8, "not 8-bit RGBA")
        let pixel = (chart.cell / 2 * image.width + chart.cell / 2) * 4
        let gray = TestPixels.rgba(image)[pixel..<pixel + 3].map(Int.init)
        return (gray.max() ?? 0) - (gray.min() ?? 0)
    }
}
