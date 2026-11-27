// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreNetwork",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreNetwork", targets: ["SieloCoreNetwork"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels")
    ],
    targets: [
        .target(
            name: "SieloCoreNetwork",
            dependencies: ["SieloCoreModels"]
        )
    ]
)
