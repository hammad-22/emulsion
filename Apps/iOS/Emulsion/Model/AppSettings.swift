import EmulsionCore
import SwiftUI

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class AppSettings {
    enum Resolution: String, CaseIterable, Identifiable {
        case standard, full
        var id: String { rawValue }
        var title: String { self == .standard ? "12 MP" : "48 MP" }
    }

    private enum Key {
        static let autoSave = "autoSave", format = "format", resolution = "resolution"
    }

    var autoSave: Bool { didSet { defaults.set(autoSave, forKey: Key.autoSave) } }
    var format: Renderer.ExportFormat { didSet { defaults.set(format.rawValue, forKey: Key.format) } }
    /// Capture resolution; read by the camera once it exists (MOV-96).
    var resolution: Resolution { didSet { defaults.set(resolution.rawValue, forKey: Key.resolution) } }

    private let defaults = UserDefaults.standard
    init() {
        autoSave = defaults.bool(forKey: Key.autoSave)
        format = Renderer.ExportFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .heic
        resolution = Resolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .standard
    }
}
