// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VidPare",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "VidPare",
            path: "Sources/VidPare"
        ),
        .testTarget(
            name: "VidPareTests",
            dependencies: ["VidPare"],
            path: "Tests/VidPareTests"
        )
    ]
)
