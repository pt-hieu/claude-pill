// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePill",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudePill"),
        .testTarget(name: "ClaudePillTests", dependencies: ["ClaudePill"]),
    ]
)
