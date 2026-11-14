#if os(iOS)
    import AVFoundation
    import Synchronization

    /// Receives viewfinder frames on the frame queue and passes the newest on, with the
    /// rotation that turns it upright.
    final class FrameDelivery: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
        let stream = SourceStream.frames()
        private let angle = Mutex<Double>(0)

        var rotationAngle: Double {
            get { angle.withLock { $0 } }
            set { angle.withLock { $0 = newValue } }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let buffer = sampleBuffer.imageBuffer else { return }
            stream.yield(CameraFrame(pixelBuffer: buffer, rotationAngle: rotationAngle))
        }
    }
#endif
