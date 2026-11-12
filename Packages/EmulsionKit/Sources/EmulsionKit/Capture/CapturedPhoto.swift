import Foundation

/// A photo file straight from the camera (a DNG on device), ready for the library.
public struct CapturedPhoto: Sendable {
    public let data: Data
    public let fileExtension: String

    public init(data: Data, fileExtension: String) {
        self.data = data
        self.fileExtension = fileExtension
    }
}
