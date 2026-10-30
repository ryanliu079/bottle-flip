// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BottleFlip",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .executable(name: "BottleFlipPreview", targets: ["BottleFlipPreview"])
    ],
    targets: [
        .target(name: "GameCore", path: "BottleFlip/Core"),
        .executableTarget(name: "BottleFlipPreview", dependencies: ["GameCore"], path: "BottleFlip/App", resources: [.copy("Sounds"), .copy("Music"), .copy("Scenery"), .copy("Shaders")]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"], path: "Tests/GameCoreTests")
    ]
)
