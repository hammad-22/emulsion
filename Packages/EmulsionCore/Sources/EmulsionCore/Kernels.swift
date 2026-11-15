import CoreImage
import Foundation

/// Precompiled Core Image Metal kernels of the film process (see EmulsionCore/Kernels/Emulsion.ci.metal
/// and Tools/build-kernels.sh).
struct Kernels {
    // Named exactly like the Metal functions in Emulsion.ci.metal.
    let filmSystem, filmSystemRelative, filmSystemPlain, filmSystemRelativePlain: CIColorKernel
    let displayToScene, inputTransform, ycbcrInputTransform: CIColorKernel
    let halationSource, halationMix, grainNoise, grainClumpNoise, lightnessGuide, localTone: CIColorKernel
    let mirroredEdges: CIWarpKernel
    let gaussianPass: CIKernel

    init(library data: Data) throws {
        func load(_ name: String) throws -> CIColorKernel { try CIColorKernel(functionName: name, fromMetalLibraryData: data) }
        filmSystem = try load("filmSystem")
        filmSystemRelative = try load("filmSystemRelative")
        filmSystemPlain = try load("filmSystemPlain")
        filmSystemRelativePlain = try load("filmSystemRelativePlain")
        displayToScene = try load("displayToScene")
        inputTransform = try load("inputTransform")
        ycbcrInputTransform = try load("ycbcrInputTransform")
        halationSource = try load("halationSource")
        halationMix = try load("halationMix")
        grainNoise = try load("grainNoise")
        grainClumpNoise = try load("grainClumpNoise")
        lightnessGuide = try load("lightnessGuide")
        localTone = try load("localTone")
        mirroredEdges = try CIWarpKernel(functionName: "mirroredEdges", fromMetalLibraryData: data)
        gaussianPass = try CIKernel(functionName: "gaussianPass", fromMetalLibraryData: data)
    }

    /// The metallib holding every process's kernels, for this platform.
    static func library() throws -> Data {
        #if os(macOS)
            let platform = "macosx"
        #elseif targetEnvironment(simulator)
            let platform = "iphonesimulator"
        #else
            let platform = "iphoneos"
        #endif
        guard let url = Bundle.module.url(forResource: "Emulsion-\(platform)", withExtension: "metallib") else {
            throw EmulsionError.kernelsMissing
        }
        return try Data(contentsOf: url)
    }

    func run(_ kernel: CIColorKernel, _ extent: CGRect, _ arguments: [Any]) throws -> CIImage {
        guard let image = kernel.apply(extent: extent, arguments: arguments) else { throw EmulsionError.renderFailed }
        return image
    }

    /// Below this σ (pixels) blurs use the exact `gaussianPass`: CIGaussianBlur's width is 0.9–1.2% off at 1.9–2.5 px (measured).
    static let exactBlurPixels = 4.0

    /// Pixels `gaussianPass` reads on each side for a Gaussian of `sigma` pixels.
    static func gaussianRadius(sigma: Double) -> Double { (4 * sigma).rounded(.up) }

    /// `image` blurred by a Gaussian of `sigma` pixels: below `exactBlurPixels` with the exact
    /// separable kernel `gaussianPass`, above with Core Image's.
    func gaussianBlur(_ image: CIImage, sigma: Double) throws -> CIImage {
        guard sigma < Self.exactBlurPixels else { return image.applyingGaussianBlur(sigma: sigma) }
        let radius = Self.gaussianRadius(sigma: sigma)
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
}
