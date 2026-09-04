// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Peek", path: "Sources/Peek")
    ]
)
