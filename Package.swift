// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kimi",
    products: [
        .executable(name: "kimi", targets: ["Kimi"])
    ],
    targets: [
        .executableTarget(
            name: "Kimi",
            path: "Sources/Kimi",
            swiftSettings: [
                // main.swift contains the explicit @main entry point.
                // Parse it as a library so Swift does not treat the filename
                // itself as a competing top-level entry point.
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "KimiTests",
            dependencies: ["Kimi"],
            path: "Tests/KimiTests"
        )
    ]
)
