// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmigoCapy",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "AmigoCapy",
            path: "Sources/AmigoCapy"
        )
    ]
)
