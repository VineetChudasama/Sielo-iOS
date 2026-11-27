// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreLyrics",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreLyrics", targets: ["SieloCoreLyrics"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels")
    ],
    targets: [
        .target(
            name: "SieloCoreLyrics",
            dependencies: ["SieloCoreModels"]
        )
    ]
)
