// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreeTubeInstaller",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FreeTubeInstaller",
            targets: ["FreeTubeApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FreeTubeApp",
            dependencies: [],
            path: "Sources/FreeTubeApp"
        )
    ]
)
