/// The app's debug launch arguments, mirroring `Emulsion/Shared/LaunchArgument.swift`.
enum LaunchArgument {
    static let componentGalleryArguments = ["--component-gallery"]
    static let libraryArguments = ["--library"]

    static func cameraScenarioArguments(_ name: String) -> [String] { ["-camera-scenario", name] }
}
