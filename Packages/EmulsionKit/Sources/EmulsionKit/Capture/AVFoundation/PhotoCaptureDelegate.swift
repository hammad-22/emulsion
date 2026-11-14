#if os(iOS)
    import AVFoundation
    import Synchronization

    /// Turns one photo capture's delegate callbacks into a single result.
    final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
        private struct State {
            var continuation: CheckedContinuation<Result<Data, CameraError>, Never>?
            var data: Data?
        }
        private let state = Mutex(State())

        func deliver(to continuation: CheckedContinuation<Result<Data, CameraError>, Never>) {
            state.withLock { $0.continuation = continuation }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            state.withLock { $0.data = data }
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?
        ) {
            let (continuation, data) = state.withLock { state in
                defer { state.continuation = nil }
                return (state.continuation, state.data)
            }
            continuation?.resume(returning: data.map(Result.success) ?? .failure(.captureFailed))
        }
    }
#endif
