// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ponder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Ponder", path: "Sources/Ponder")
    ]
)
