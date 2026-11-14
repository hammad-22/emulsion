import CoreImage
import Foundation

/// The digicam kernels (Digicam.ci.metal), named like their Metal functions without the prefix.
struct DigicamKernels {
    let fringeSource, fringe, capture, encodedLuma, sharpen: CIColorKernel

    init(library data: Data) throws {
        func load(_ name: String) throws -> CIColorKernel { try CIColorKernel(functionName: name, fromMetalLibraryData: data) }
        fringeSource = try load("digicamFringeSource")
        fringe = try load("digicamFringe")
        capture = try load("digicamCapture")
        encodedLuma = try load("digicamEncodedLuma")
        sharpen = try load("digicamSharpen")
    }
}
