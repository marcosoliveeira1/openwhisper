// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenWhisper",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "OpenWhisper",
            path: "Sources/OpenWhisper"
        )
    ]
)
