// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Glide",
            path: "Sources/Glide"
        )
    ]
)
