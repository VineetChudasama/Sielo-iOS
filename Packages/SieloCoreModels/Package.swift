// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreModels",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreModels", targets: ["SieloCoreModels"])
    ],
    targets: [
        .target(name: "SieloCoreModels")
    ]
)
