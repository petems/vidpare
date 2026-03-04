// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VidPare",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VidPare",
            path: "Sources/VidPare"
        ),
        .target(
            name: "AXAutomation",
            path: "Sources/AXAutomation"
        ),
        .executableTarget(
            name: "DemoRecorder",
            dependencies: ["AXAutomation"],
            path: "Sources/DemoRecorder"
        ),
        .testTarget(
            name: "VidPareTests",
            dependencies: [
                "VidPare",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/VidPareTests",
            exclude: ["__Snapshots__"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "VidPareAcceptanceTests",
            dependencies: ["AXAutomation"],
            path: "Tests/VidPareAcceptanceTests"
        ),
    ]
)
