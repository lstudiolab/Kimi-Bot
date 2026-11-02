// swift-tools-version: 5.9
import PackageDescription
let package = Package(
 name: "Kimi",
 products: [.executable(name: "kimi", targets: ["Kimi"])],
 targets: [
  .executableTarget(name: "Kimi", path: "Sources/Kimi"),
  .testTarget(name: "KimiTests", dependencies: ["Kimi"], path: "Tests/KimiTests")
 ]
)
