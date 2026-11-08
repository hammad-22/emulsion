import AVFoundation
import CoreVideo
import VideoToolbox

/// Synthetic 10-bit Y′CbCr movies: flat patches of chosen code values, written with
/// AVAssetWriter and read back without conversion. Both codecs round-trip flat patches
/// exactly in their native layout (checked by `VideoSignalTests`).
public enum VideoFixtures {
    public enum Codec: Sendable, CaseIterable {
        /// HEVC Main10, 4:2:0; carries legal or full range.
        case hevcMain10
        /// ProRes 422 HQ, 4:2:2; legal range only (the writer converts full range).
        case proRes422HQ

        var codecType: AVVideoCodecType { self == .hevcMain10 ? .hevc : .proRes422HQ }

        func pixelFormat(fullRange: Bool) -> OSType {
            switch (self, fullRange) {
            case (.hevcMain10, false): return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            case (.hevcMain10, true): return kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            case (.proRes422HQ, false): return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
            case (.proRes422HQ, true): return kCVPixelFormatType_422YpCbCr10BiPlanarFullRange
            }
        }
    }

    /// Patch edge in pixels: a multiple of the codecs' block sizes, so each patch's center is flat.
    public static let patchSize = 64

    /// The center pixel of patch `index`, in Core Image coordinates.
    public static func center(ofPatch index: Int) -> (x: Int, y: Int) { (index * patchSize + patchSize / 2, patchSize / 2) }

    /// Writes one frame of side-by-side patches (10-bit Y′, Cb, Cr codes) and reads it back.
    /// `matrixTag` is an `AVVideoYCbCrMatrix_*` value; it is written to the file and comes back
    /// as the frame's `kCVImageBufferYCbCrMatrixKey`.
    public static func roundTrip(
        _ patches: [SIMD3<UInt16>], codec: Codec, fullRange: Bool, matrixTag: String
    ) async throws -> CVPixelBuffer {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("emulsion-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = codec.pixelFormat(fullRange: fullRange)
        try await write(frame(patches, format: format), to: url, codec: codec, matrixTag: matrixTag)
        return try await firstFrame(of: url, format: format)
    }

    static func frame(_ patches: [SIMD3<UInt16>], format: OSType) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, patches.count * patchSize, patchSize, format, attributes, &created)
        guard let buffer = created else { throw FixtureError.pixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        for plane in 0..<2 {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { throw FixtureError.pixelBuffer }
            let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) / 2
            let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
            let samples = base.assumingMemoryBound(to: UInt16.self)
            let patchWidth = width / patches.count
            for y in 0..<CVPixelBufferGetHeightOfPlane(buffer, plane) {
                for x in 0..<width {
                    // 10-bit codes sit in the high bits of each 16-bit sample.
                    let code = patches[x / patchWidth]
                    if plane == 0 {
                        samples[y * row + x] = code.x << 6
                    } else {
                        samples[y * row + 2 * x] = code.y << 6
                        samples[y * row + 2 * x + 1] = code.z << 6
                    }
                }
            }
        }
        return buffer
    }

    private static func write(_ frame: CVPixelBuffer, to url: URL, codec: Codec, matrixTag: String) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let wide = matrixTag == AVVideoYCbCrMatrix_ITU_R_2020
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.codecType, AVVideoWidthKey: CVPixelBufferGetWidth(frame),
            AVVideoHeightKey: CVPixelBufferGetHeight(frame),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: wide ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: matrixTag,
            ],
        ]
        if codec == .hevcMain10 {
            settings[AVVideoCompressionPropertiesKey] = [
                kVTCompressionPropertyKey_ProfileLevel as String: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoQualityKey: 1.0,
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writer }
        writer.startSession(atSourceTime: .zero)
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard adaptor.append(frame, withPresentationTime: .zero) else { throw writer.error ?? FixtureError.writer }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writer }
    }

    private static func firstFrame(of url: URL, format: OSType) async throws -> CVPixelBuffer {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw FixtureError.reader }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: format])
        reader.add(output)
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(), let buffer = sample.imageBuffer else {
            throw reader.error ?? FixtureError.reader
        }
        return buffer
    }

    enum FixtureError: Error { case pixelBuffer, writer, reader }
}
