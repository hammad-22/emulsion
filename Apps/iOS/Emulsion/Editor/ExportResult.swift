import SwiftUI

enum ExportResult: Equatable {
    case saved
    case failed(String)

    var message: String {
        switch self {
        case .saved: String(localized: "Saved to Photos")
        case .failed(let message): message
        }
    }

    var feedback: SensoryFeedback {
        switch self {
        case .saved: .success
        case .failed: .error
        }
    }
}
