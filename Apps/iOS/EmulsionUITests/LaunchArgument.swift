/// The app's debug launch arguments, mirroring `Emulsion/Shared/LaunchArgument.swift`.
enum LaunchArgument {
    static let componentGallery = ["--component-gallery"]
    static let library = ["--library"]

    static func cameraScenario(_ name: String) -> [String] { ["-camera-scenario", name] }
}
