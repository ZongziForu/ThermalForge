// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ThermalForge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ThermalForgeCore",
            path: "Sources/ThermalForgeCore",
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),
        .executableTarget(
            name: "thermalforge",
            dependencies: [
                "ThermalForgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/thermalforge"
        ),
        .executableTarget(
            name: "ThermalForgeApp",
            dependencies: ["ThermalForgeCore", "ThermalForgeTouchBar"],
            path: "Sources/ThermalForgeApp"
        ),
        .target(name: "ThermalForgeTouchBar", dependencies: ["ThermalForgeCore"]),
        .executableTarget(name: "TouchBarPreview", dependencies: ["ThermalForgeTouchBar"],
                          path: "Tools/TouchBarPreview"),
        .testTarget(
            name: "ThermalForgeTests",
            dependencies: ["ThermalForgeCore", "ThermalForgeTouchBar"],
            path: "Tests/ThermalForgeTests"
        ),
    ]
)
