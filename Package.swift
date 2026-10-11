// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmigoClick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AmigoClick",
            path: "Sources/AmigoClick"
        )
    ]
)
