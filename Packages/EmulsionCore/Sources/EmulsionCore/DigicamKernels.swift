import CoreImage
import Foundation

/// The digicam process's kernels (EmulsionCore/Kernels/Digicam.ci.metal), linked into the same
/// metallib as the film kernels (Tools/build-kernels.sh).
struct DigicamKernels {
    // Named exactly like the Metal functions in Digicam.ci.metal.
    let fringeSource, capture, encodedLuma, sharpen: CIColorKernel

    init(library data: Data) throws {
        func load(_ name: String) throws -> CIColorKernel { try CIColorKernel(functionName: name, fromMetalLibraryData: data) }
        fringeSource = try load("digicamFringeSource")
        capture = try load("digicamCapture")
        encodedLuma = try load("digicamEncodedLuma")
        sharpen = try load("digicamSharpen")
    }
}
