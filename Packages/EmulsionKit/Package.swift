// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmulsionKit",
    defaultLocalization: "en",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "EmulsionKit", targets: ["EmulsionKit"])
    ],
    dependencies: [
        .package(path: "../EmulsionCore")
    ],
    targets: [
        .target(name: "EmulsionKit", dependencies: ["EmulsionCore"], resources: [.copy("Resources/Samples")]),
        .testTarget(
            name: "EmulsionKitTests",
            dependencies: ["EmulsionKit", .product(name: "EmulsionFixtures", package: "EmulsionCore")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
