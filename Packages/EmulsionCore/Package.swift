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
        // Offline stock data and fitting. Deliberately not a library product: the datasheet data must never reach an app bundle.
        .target(name: "EmulsionFit", resources: [.copy("Resources/StockData")]),
        .testTarget(
            name: "EmulsionCoreTests", dependencies: ["EmulsionCore", "EmulsionFixtures"],
            resources: [.copy("References"), .copy("Goldens"), .copy("Scenes")]),
        .testTarget(name: "EmulsionFitTests", dependencies: ["EmulsionFit"]),
    ],
    swiftLanguageModes: [.v6]
)
