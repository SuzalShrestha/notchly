// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Notchly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Notchly", path: "Sources/Notchly"),
    ]
)
