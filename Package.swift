// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kimi",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "kimi", targets: ["Kimi"])],
    dependencies: [
        .package(url: "https://github.com/DiscordBM/DiscordBM", from: "1.16.2")
    ],
    targets: [
        .executableTarget(
            name: "Kimi",
            dependencies: [.product(name: "DiscordBM", package: "DiscordBM")],
            path: "Sources/Kimi"
        ),
        .testTarget(name: "KimiTests", dependencies: ["Kimi"], path: "Tests/KimiTests")
    ]
)
