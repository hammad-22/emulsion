import EmulsionCore
import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
public final class AppSettings {
    public enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case standard, full
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .standard: String(localized: "12 MP", bundle: .module, comment: "Capture resolution in megapixels")
            case .full: String(localized: "48 MP", bundle: .module, comment: "Capture resolution in megapixels")
            }
        }
    }

    private enum Key {
        static let autoSave = "autoSave", format = "format", resolution = "resolution"
    }

    public var autoSave: Bool { didSet { defaults.set(autoSave, forKey: Key.autoSave) } }
    public var format: Renderer.ExportFormat { didSet { defaults.set(format.rawValue, forKey: Key.format) } }
    /// The camera's capture resolution; lenses without 48 MP capture at 12 MP.
    public var resolution: Resolution { didSet { defaults.set(resolution.rawValue, forKey: Key.resolution) } }

    private let defaults = UserDefaults.standard
    public init() {
        autoSave = defaults.bool(forKey: Key.autoSave)
        format = Renderer.ExportFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .heic
        resolution = Resolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .standard
    }
}
