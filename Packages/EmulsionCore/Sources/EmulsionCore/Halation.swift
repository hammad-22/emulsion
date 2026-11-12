import CoreImage
import Foundation
import simd

/// Halation: light that crosses the emulsion, reflects at the back of the base and re-exposes the
/// emulsion from behind (`docs/FILM-THEORY.md` §6.1). Linear in exposure: no threshold, no limiter.
/// The film kernels add the glow to each layer's exposure (`exposeLayers`); the kernels
/// `halationSource`, `halationMix` and `exposureWithHalation` mirror this; names match.
enum Halation {
    /// The spread of the returned light: a unit-volume sum of 2D Gaussians, sigmas in base
    /// thicknesses. The 3-Gaussian fit (one negative weight) of the derived single-bounce profile,
    /// max |Δ encircled energy| 0.0615 (`Tools/halation-kernel`, `recommended`).
    static let weights = SIMD3<Double>(-0.99816922, 1.7270851, 0.27108408)
    static let sigmasInBaseThicknesses = SIMD3<Double>(1.3078016, 1.7310926, 6.10456)
    private static let variances = sigmasInBaseThicknesses * sigmasInBaseThicknesses

    /// Film base thickness. Estimated: a typical triacetate camera-film base; the VISION3 sheets
    /// do not state it.
    static let baseThicknessMicrometres = 140.0
    /// Share of diffuse light entering a base of index 1.48 that its back surface returns to the
    /// emulsion (Fresnel plus total internal reflection), derived in `Tools/halation-kernel`
    /// (`geometry.returned_fraction`).
    static let returnFraction = 0.584
    /// Green layer's share of the red layer's halation. Estimated: the green layer sits above the
    /// red one, so the returning light reaches it second.
    static let greenShare = 0.25

    /// Kernel value h·t² at `radius` base thicknesses (per unit returned light).
    static func profile(radiusInBaseThicknesses radius: Double) -> Double {
        let gaussians = (0..<3).map { exp(-radius * radius / (2 * variances[$0])) / (2 * .pi * variances[$0]) }
        return simd_dot(weights, SIMD3(gaussians))
    }

    /// Share of the returned light that lands within `radius` base thicknesses.
    static func encircledEnergy(radiusInBaseThicknesses radius: Double) -> Double {
        simd_dot(weights, SIMD3((0..<3).map { 1 - exp(-radius * radius / (2 * variances[$0])) }))
    }

    /// Image pixels per base thickness.
    static func pixelsPerBaseThickness(longEdge: Double) -> Double {
        baseThicknessMicrometres / FilmLook.micrometresPerPixel(longEdge: longEdge)
    }

    /// k per layer (red, green, blue): returned light per unit of the exposing light. The amount
    /// (0…1) reads as the share of the exposing light that scatters into the base (a modelling
    /// assumption). Blue is 0: the yellow filter layer stops blue light above the green and red layers.
    static func layerReturn(amount: Double, backing: AntihalationBacking) -> SIMD3<Double> {
        let red = amount * returnFraction * backing.returnFraction
        return SIMD3(red, red * greenShare, 0)
    }

    /// Layer exposure with its halation: E′ = (E + k·glow) / (1 + k). Film speed is defined on
    /// uniform patches, which already include their own halation, so a uniform field is unchanged.
    static func exposureWithHalation(_ exposure: SIMD3<Double>, glow: SIMD3<Double>, layerReturn k: SIMD3<Double>) -> SIMD3<Double> {
        (exposure + k * glow) / (1 + k)
    }

    /// The film kernels' `k` and the rows of the inverse sensitivity, which carry the change of
    /// layer exposure back to the light highlight chroma retention sees.
    static func kernelArguments(amount: Double, backing: AntihalationBacking) -> [CIVector] {
        [CIVector(layerReturn(amount: amount, backing: backing), w: 0)] + CIVector.rows(of: FilmLook.stock.sensitivity.inverse)
    }

    /// A blur is taken at reduced scale, halving the image while the blur stays at least this many
    /// reduced pixels wide, at most `maxHalvings` times. Measured: allowing 5 halvings was no faster
    /// at 4032×3024 (the blurs then sit at different scales, so they are mixed at full size).
    static let minBlurPixels = 2.0
    static let maxHalvings = 3

    /// Halvings before a Gaussian of `sigma` image pixels.
    static func halvings(sigma: Double) -> Int {
        (0...maxHalvings).last { $0 == 0 || sigma / pow(2, Double($0)) >= minBlurPixels } ?? 0
    }

    /// The Gaussian, in reduced pixels after `halvings`, whose result has sigma `sigma` in image
    /// pixels: narrowed by the variance the halvings (a box of N px: (N² − 1)/12) and the bilinear
    /// return (N²/6) add.
    static func reducedSigma(_ sigma: Double, halvings: Int) -> Double {
        let n = pow(2, Double(halvings))
        let added = halvings == 0 ? 0 : (n * n - 1) / 12 + n * n / 6
        return max(sigma * sigma - added, 0).squareRoot() / n
    }
}

extension Kernels {
    /// The halation glow G over `scene`'s extent: rgb = the layer exposure without the exposure
    /// control (kernel `halationSource`, at the Color control's `saturation`) blurred by the profile,
    /// sized to the image's long edge. The film kernels clamp it at 0 and add it to the layer
    /// exposure; it is unclamped here, because one of the profile's weights is negative.
    func halationGlow(of scene: CIImage, saturation: Double) throws -> CIImage {
        let extent = scene.extent
        let source = try run(halationSource, extent, [scene] + CIVector.rows(of: FilmLook.stock.sensitivity) + [saturation])
        let pixelsPerBase = Halation.pixelsPerBaseThickness(longEdge: max(extent.width, extent.height))
        let sigmas = (0..<3).map { Halation.sigmasInBaseThicknesses[$0] * pixelsPerBase }
        let levels = sigmas.map { Halation.halvings(sigma: $0) }
        let pyramid = try mirroredPyramid(source, levels: levels)
        let blurs = zip(sigmas, levels).map { sigma, level in
            pyramid[level].applyingGaussianBlur(sigma: Halation.reducedSigma(sigma, halvings: level))
        }
        let weights = CIVector(Halation.weights, w: 0)
        if let level = levels.first, levels.allSatisfy({ $0 == level }) {
            // One scale: mix the blurs there, then return to full size once.
            let n = pow(2, CGFloat(level))
            let reduced = extent.applying(CGAffineTransform(scaleX: 1 / n, y: 1 / n)).insetBy(dx: -1, dy: -1).integral
            return try run(halationMix, reduced, blurs + [weights]).transformed(by: CGAffineTransform(scaleX: n, y: n)).cropped(to: extent)
        }
        let returned = zip(blurs, levels).map { blur, level in
            blur.transformed(by: CGAffineTransform(scaleX: pow(2, CGFloat(level)), y: pow(2, CGFloat(level)))).cropped(to: extent)
        }
        return try run(halationMix, extent, returned + [weights])
    }

    /// `image` reflected at its edges, repeating without end, and its halvings: element i is halved
    /// i times, up to the largest of `levels`. When no level is 0 and the extent is even, the image
    /// is mirrored after the first halving (the 2×2 average commutes with the reflection then), and
    /// element 0 is not mirrored.
    private func mirroredPyramid(_ image: CIImage, levels: [Int]) throws -> [CIImage] {
        let e = image.extent
        let even = [e.minX, e.minY, e.width, e.height].allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 }
        var pyramid =
            (levels.min() ?? 0) > 0 && even ? [image, try mirroredToInfinity(image.halved())] : [try mirroredToInfinity(image)]
        while pyramid.count <= levels.max() ?? 0 { pyramid.append(pyramid[pyramid.count - 1].halved()) }
        return pyramid
    }

    /// `image` reflected at its edges, repeating without end (the warp `mirroredEdges`). Unlike
    /// clamping, a bright border pixel is not repeated to infinity (review F-12), and a uniform
    /// field stays uniform up to the border.
    private func mirroredToInfinity(_ image: CIImage) throws -> CIImage {
        let e = image.extent
        guard
            let mirrored = mirroredEdges.apply(
                extent: .infinite, roiCallback: { _, _ in e }, image: image.clampedToExtent().samplingNearest(),
                arguments: [CIVector(cgRect: e)])
        else { throw EmulsionError.renderFailed }
        // An intermediate, so a later scale is not folded into the warp's nearest sampling.
        return mirrored.insertingIntermediate(cache: false)
    }
}
