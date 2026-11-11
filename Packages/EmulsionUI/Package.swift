// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmulsionUI",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "EmulsionUI", targets: ["EmulsionUI"])
    ],
    dependencies: [
        .package(path: "../EmulsionCore"),
        .package(path: "../EmulsionKit"),
    ],
    targets: [
        .target(name: "EmulsionUI", dependencies: ["EmulsionCore", "EmulsionKit"]),
        .testTarget(name: "EmulsionUITests", dependencies: ["EmulsionUI"]),
    ],
    swiftLanguageModes: [.v6]
)
