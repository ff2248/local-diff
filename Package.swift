// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalDiff",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "DiffCore"),
        .target(name: "DiffEditor", dependencies: ["DiffCore"]),
        .executableTarget(name: "LocalDiffApp", dependencies: ["DiffCore", "DiffEditor"]),
        .testTarget(name: "DiffCoreTests", dependencies: ["DiffCore"]),
        .testTarget(name: "DiffEditorTests", dependencies: ["DiffCore", "DiffEditor"]),
    ]
)
