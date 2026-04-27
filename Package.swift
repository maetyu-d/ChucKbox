// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChuckDAW",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ChuckDAWApp", targets: ["ChuckDAWApp"])
    ],
    targets: [
        .executableTarget(
            name: "ChuckDAWApp",
            path: "Sources/ChuckDAWApp"
        )
    ]
)
