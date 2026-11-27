// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreRecommendations",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreRecommendations", targets: ["SieloCoreRecommendations"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels"),
        .package(path: "../SieloCoreDatabase"),
        .package(path: "../SieloCoreNetwork")
    ],
    targets: [
        .target(
            name: "SieloCoreRecommendations",
            dependencies: ["SieloCoreModels", "SieloCoreDatabase", "SieloCoreNetwork"]
        )
    ]
)
