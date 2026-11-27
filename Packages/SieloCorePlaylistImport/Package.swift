// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCorePlaylistImport",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCorePlaylistImport", targets: ["SieloCorePlaylistImport"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels"),
        .package(path: "../SieloCoreNetwork")
    ],
    targets: [
        .target(
            name: "SieloCorePlaylistImport",
            dependencies: ["SieloCoreModels", "SieloCoreNetwork"]
        )
    ]
)
