// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DokployRadar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DokployRadar",
            targets: ["DokployRadar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DokployRadar"
        ),
        .testTarget(
            name: "DokployRadarTests",
            dependencies: ["DokployRadar"]
        )
    ]
)
