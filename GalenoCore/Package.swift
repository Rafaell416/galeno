// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GalenoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GalenoCore", targets: ["GalenoCore"])
    ],
    targets: [
        .target(name: "GalenoCore"),
        .testTarget(name: "GalenoCoreTests", dependencies: ["GalenoCore"])
    ]
)
