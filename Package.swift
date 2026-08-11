// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CrocGUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CrocGUI", targets: ["CrocGUI"])
    ],
    targets: [
        .executableTarget(
            name: "CrocGUI",
            path: "Sources/CrocGUI"
        ),
        .testTarget(
            name: "CrocGUITests",
            dependencies: ["CrocGUI"],
            path: "Tests/CrocGUITests"
        )
    ]
)
