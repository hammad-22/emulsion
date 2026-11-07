// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmulsionCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "EmulsionCore", targets: ["EmulsionCore"]),
        .library(name: "EmulsionFixtures", targets: ["EmulsionFixtures"]),
    ],
    targets: [
        .target(name: "EmulsionCore", resources: [.process("Resources")]),
        .target(name: "EmulsionFixtures"),
        .testTarget(name: "EmulsionCoreTests", dependencies: ["EmulsionCore", "EmulsionFixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
