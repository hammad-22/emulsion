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
    static let baseReturnFraction = 0.584
    /// Green layer's share of the red layer's halation. ESTIMATED, an artistic choice made by eye, not
    /// a measurement: the green layer sits above the red one, so the returning light reaches it
    /// second. In night photographs on a negative with the backing removed (looked at, not stored),
    /// halos around point lights are saturated red discs with a white core; at 0.25 the unbacked halo
    /// at amount 1 turned orange-yellow next to the source.
    static let greenShare = 0.1

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
        let red = amount * baseReturnFraction * backing.returnFraction
        return SIMD3(red, red * greenShare, 0)
    }

    /// Layer exposure with its halation: E′ = (E + k·glow) / (1 + k). Film speed is defined on
    /// uniform patches, which already include their own halation, so a uniform field is unchanged.
    static func exposureWithHalation(_ exposure: SIMD3<Double>, glow: SIMD3<Double>, layerReturn k: SIMD3<Double>) -> SIMD3<Double> {
        (exposure + k * glow) / (1 + k)
    }

    /// The film kernels' `k` and the rows of `model`'s inverse sensitivity, which carry the change of
    /// layer exposure back to the light highlight chroma retention sees.
    static func kernelArguments(for model: FilmModel, amount: Double, backing: AntihalationBacking) -> [CIVector] {
        [CIVector(layerReturn(amount: amount, backing: backing), w: 0)] + model.inverseSensitivityRows
    }

    /// A blur is taken at reduced scale, halving the image while the blur stays at least this many
    /// reduced pixels wide, at most `maxHalvings` times. Measured: allowing 5 halvings was no faster
    /// at 4032×3024 (the blurs then sit at different scales, so they are mixed at full size).
    static let minBlurPixels = 2.0
    static let maxHalvings = 3
    /// Blurs narrower than this (reduced pixels) use the exact kernel `gaussianPass`: CIGaussianBlur's
    /// width was measured 0.9–1.2% off at 1.9–2.5 px and within 0.5% from 3.8 px up.
    static let exactBlurPixels = 4.0

    /// The pixels of `extent` (rounded out to whole pixels) that the reflection at its edges (kernel
    /// `mirroredEdges`) reads to fill `rect`: the rect itself inside, its reflection at the edges
    /// within one image width or height, all of `extent` beyond. Asking for all of it for every tile kept a whole full-resolution
    /// intermediate (review B6).
    static func mirroredSource(of rect: CGRect, in extent: CGRect) -> CGRect {
        func reflected(_ lo: CGFloat, _ hi: CGFloat, _ start: CGFloat, _ end: CGFloat) -> (CGFloat, CGFloat) {
            guard lo >= start - (end - start), hi <= end + (end - start) else { return (start, end) }
            var (from, to) = (max(lo, start), min(hi, end))
            if lo < start { (from, to) = (min(from, start), max(to, 2 * start - lo)) }
            if hi > end { (from, to) = (min(from, 2 * end - hi), max(to, end)) }
            return (max(from, start), min(to, end))
        }
        guard !rect.isInfinite, !rect.isNull else { return extent }
        // One pixel more on each side for the nearest sampling at pixel edges.
        let wide = rect.insetBy(dx: -1, dy: -1)
        let x = reflected(wide.minX, wide.maxX, extent.minX, extent.maxX)
        let y = reflected(wide.minY, wide.maxY, extent.minY, extent.maxY)
        return CGRect(x: x.0, y: y.0, width: max(x.1 - x.0, 0), height: max(y.1 - y.0, 0)).integral
    }

    /// Halvings before each of the profile's Gaussians (`sigmas` in image pixels). The first two
    /// nearly cancel (weights −1.0 and +1.7), so they share the coarser of their levels: blurred at
    /// one scale, their halving and return errors cancel too (measured at 512 px: 0.26% of the peak
    /// vs 0.91% at separate levels).
    static func levels(sigmas: [Double]) -> [Int] {
        var levels = sigmas.map { halvings(sigma: $0) }
        let pair = max(levels[0], levels[1])
        (levels[0], levels[1]) = (pair, pair)
        return levels
    }

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
    /// The halation glow G over `scene`'s extent: rgb = `model`'s layer exposure without the exposure
    /// control (kernel `halationSource`, at the Color control's `saturation`) blurred by the profile,
    /// sized to the image's long edge. The film kernels clamp it at 0 and add it to the layer
    /// exposure; it is unclamped here, because one of the profile's weights is negative.
    func halationGlow(of scene: CIImage, model: FilmModel, saturation: Double) throws -> CIImage {
        let extent = scene.extent
        let source = try run(halationSource, extent, [scene] + CIVector.rows(of: model.sensitivity) + [saturation])
        let pixelsPerBase = Halation.pixelsPerBaseThickness(longEdge: max(extent.width, extent.height))
        let sigmas = (0..<3).map { Halation.sigmasInBaseThicknesses[$0] * pixelsPerBase }
        let levels = Halation.levels(sigmas: sigmas)
        let pyramid = try mirroredPyramid(source, levels: levels)
        let blurs = try zip(sigmas, levels).map { sigma, level in
            try gaussianBlur(pyramid[level], sigma: Halation.reducedSigma(sigma, halvings: level))
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

    /// `image` blurred by a Gaussian of `sigma` pixels: below `Halation.exactBlurPixels` with the exact
    /// separable kernel `gaussianPass`, above with Core Image's.
    private func gaussianBlur(_ image: CIImage, sigma: Double) throws -> CIImage {
        guard sigma < Halation.exactBlurPixels else { return image.applyingGaussianBlur(sigma: sigma) }
        let radius = (4 * sigma).rounded(.up)
        func pass(_ input: CIImage, _ step: CIVector) throws -> CIImage {
            guard
                let output = gaussianPass.apply(
                    extent: input.extent, roiCallback: { _, rect in rect.insetBy(dx: -radius * step.x, dy: -radius * step.y) },
                    arguments: [input, step, sigma])
            else { throw EmulsionError.renderFailed }
            return output
        }
        return try pass(pass(image, CIVector(x: 1, y: 0)), CIVector(x: 0, y: 1))
    }

    /// `image` reflected at its edges, repeating without end, and its halvings: element i is halved
    /// i times, up to the largest of `levels`. When no level is 0 and the origin is even, the image
    /// is mirrored after the first halving, so no full-resolution mirror is kept (review B6). An odd
    /// width or height is first extended by its edge pixel (what the reflection puts there) to an
    /// even one; the halved image is then reflected about the original edge, half a pixel inside
    /// its last pixel's centre, which is exactly the halving of the reflected image. Element 0 is
    /// then not mirrored.
    private func mirroredPyramid(_ image: CIImage, levels: [Int]) throws -> [CIImage] {
        let e = image.extent
        let evenOrigin = [e.minX, e.minY].allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 }
        var pyramid: [CIImage]
        if (levels.min() ?? 0) > 0 && evenOrigin {
            let padded = CGRect(x: e.minX, y: e.minY, width: (e.width / 2).rounded(.up) * 2, height: (e.height / 2).rounded(.up) * 2)
            let halved = image.clampedToExtent().cropped(to: padded).halved()
            let mirror = e.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
            pyramid = [image, try mirroredToInfinity(halved, about: mirror)]
        } else {
            pyramid = [try mirroredToInfinity(image, about: e)]
        }
        while pyramid.count <= levels.max() ?? 0 { pyramid.append(pyramid[pyramid.count - 1].halved()) }
        return pyramid
    }

    /// `image` reflected at the edges of `mirror` (inside its extent; pixel centres or half-way
    /// between them), repeating without end (the warp `mirroredEdges`). Unlike clamping, a bright
    /// border pixel is not repeated to infinity (review F-12), and a uniform field stays uniform up
    /// to the border.
    private func mirroredToInfinity(_ image: CIImage, about mirror: CGRect) throws -> CIImage {
        let pixels = image.extent
        guard
            let mirrored = mirroredEdges.apply(
                extent: .infinite,
                roiCallback: { _, rect in Halation.mirroredSource(of: rect, in: mirror).intersection(pixels) },
                image: image.clampedToExtent().samplingNearest(), arguments: [CIVector(cgRect: mirror)])
        else { throw EmulsionError.renderFailed }
        // An intermediate, so a later scale is not folded into the warp's nearest sampling.
        return mirrored.insertingIntermediate(cache: false)
    }
}
