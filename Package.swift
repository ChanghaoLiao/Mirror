// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mirror",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mirror", targets: ["Mirror"])],
    targets: [
        .target(name: "MirrorCore"),
        .executableTarget(name: "Mirror", dependencies: ["MirrorCore"]),
        .testTarget(name: "MirrorCoreTests", dependencies: ["MirrorCore"]),
        .testTarget(name: "MirrorAppTests", dependencies: ["Mirror", "MirrorCore"]),
    ],
    swiftLanguageModes: [.v5]
)
