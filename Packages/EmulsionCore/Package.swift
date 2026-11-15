// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmulsionCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "EmulsionCore", targets: ["EmulsionCore"]),
        .library(name: "EmulsionFixtures", targets: ["EmulsionFixtures"]),
        .executable(name: "emulsion-fit", targets: ["emulsion-fit"]),
    ],
    targets: [
        .target(name: "EmulsionCore", resources: [.process("Resources")]),
        .target(name: "EmulsionFixtures"),
        // Offline stock fitting; not a library product, so datasheet data never reaches an app.
        .target(
            name: "EmulsionFit", dependencies: ["EmulsionCore"],
            resources: [.copy("Resources/StockData"), .copy("Resources/standards-manifest.json")]),
        .executableTarget(name: "emulsion-fit", dependencies: ["EmulsionFit"]),
        .testTarget(
            name: "EmulsionCoreTests", dependencies: ["EmulsionCore", "EmulsionFixtures"],
            resources: [.copy("References"), .copy("Goldens"), .copy("Scenes")]),
        .testTarget(name: "EmulsionFitTests", dependencies: ["EmulsionFit", "EmulsionCore"]),
    ],
    swiftLanguageModes: [.v6]
)
