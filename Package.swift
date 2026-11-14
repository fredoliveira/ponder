// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overlay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Overlay", path: "Sources/Overlay")
    ]
)
