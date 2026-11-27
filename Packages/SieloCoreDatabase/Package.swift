// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SieloCoreDatabase",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SieloCoreDatabase", targets: ["SieloCoreDatabase"])
    ],
    dependencies: [
        .package(path: "../SieloCoreModels"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "SieloCoreDatabase",
            dependencies: [
                "SieloCoreModels",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
