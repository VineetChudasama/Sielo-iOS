// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreAudio",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreAudio", targets: ["SieloCoreAudio"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels"),
        .package(path: "../SieloCoreNetwork"),
        .package(path: "../SieloCoreDatabase")
    ],
    targets: [
        .target(
            name: "SieloCoreAudio",
            dependencies: ["SieloCoreModels", "SieloCoreNetwork", "SieloCoreDatabase"]
        )
    ]
)
