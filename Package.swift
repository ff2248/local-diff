// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalDiff",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "DiffCore"),
        .executableTarget(name: "LocalDiffApp", dependencies: ["DiffCore"]),
        .testTarget(name: "DiffCoreTests", dependencies: ["DiffCore"]),
    ]
)
