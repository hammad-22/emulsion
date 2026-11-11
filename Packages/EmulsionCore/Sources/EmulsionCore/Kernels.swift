import CoreImage
import Foundation

/// Precompiled Core Image Metal kernels (see EmulsionCore/Kernels/Emulsion.ci.metal and
/// scripts/build-kernels.sh).
struct Kernels {
    // Named exactly like the Metal functions in Emulsion.ci.metal.
    let filmSystem, filmSystemRelative, displayToScene, inputTransform, ycbcrInputTransform: CIColorKernel
    let halationSource, halationAdd, grain, lightnessGuide, localTone: CIColorKernel

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
        displayToScene = try load("displayToScene")
        inputTransform = try load("inputTransform")
        ycbcrInputTransform = try load("ycbcrInputTransform")
        halationSource = try load("halationSource")
        halationAdd = try load("halationAdd")
        grain = try load("grain")
        lightnessGuide = try load("lightnessGuide")
        localTone = try load("localTone")
    }

    func run(_ kernel: CIColorKernel, _ extent: CGRect, _ arguments: [Any]) throws -> CIImage {
        guard let image = kernel.apply(extent: extent, arguments: arguments) else { throw EmulsionError.renderFailed }
        return image
    }
}
