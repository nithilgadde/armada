// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "armada",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "armada",
            targets: ["Armada"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Armada",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Armada",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
