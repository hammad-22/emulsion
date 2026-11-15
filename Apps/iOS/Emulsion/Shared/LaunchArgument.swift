import Foundation

/// Debug launch arguments, mirrored in `EmulsionUITests/LaunchArgument.swift`.
enum LaunchArgument {
    static let componentGallery = "--component-gallery"
    static let library = "--library"
    static let viewfinderTiming = "--viewfinder-timing"
    /// Read as a `UserDefaults` key: launch with `-camera-scenario <name>`.
    static let cameraScenario = "camera-scenario"

    static func isPresent(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}
