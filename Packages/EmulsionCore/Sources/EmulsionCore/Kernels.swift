import CoreImage
import Foundation

/// Precompiled Core Image Metal kernels (see EmulsionCore/Kernels/Emulsion.ci.metal and
/// Tools/build-kernels.sh).
struct Kernels {
    // Named exactly like the Metal functions in Emulsion.ci.metal.
    let filmSystem, filmSystemRelative, filmSystemPlain, filmSystemRelativePlain: CIColorKernel
    let displayToScene, inputTransform, ycbcrInputTransform: CIColorKernel
    let halationSource, halationMix, grainNoise, lightnessGuide, localTone: CIColorKernel
    let mirroredEdges: CIWarpKernel
    let gaussianPass: CIKernel

    init() throws {
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
        let data = try Data(contentsOf: url)
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
        lightnessGuide = try load("lightnessGuide")
        localTone = try load("localTone")
        mirroredEdges = try CIWarpKernel(functionName: "mirroredEdges", fromMetalLibraryData: data)
        gaussianPass = try CIKernel(functionName: "gaussianPass", fromMetalLibraryData: data)
    }

    func run(_ kernel: CIColorKernel, _ extent: CGRect, _ arguments: [Any]) throws -> CIImage {
        guard let image = kernel.apply(extent: extent, arguments: arguments) else { throw EmulsionError.renderFailed }
        return image
    }
}
