import Foundation
import Photos

/// Add-only access: Emulsion never reads the user's library.
public enum PhotoLibrarySaver {
    public enum Failure: LocalizedError {
        case denied
        public var errorDescription: String? { "Allow Emulsion to add photos in Settings to save exports." }
    }

    public static func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
