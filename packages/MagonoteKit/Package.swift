// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagonoteKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MagonoteKit",
            targets: ["MagonoteKit"]
        ),
    ],
    targets: [
        .target(
            name: "MagonoteKit"
        ),
        .testTarget(
            name: "MagonoteKitTests",
            dependencies: ["MagonoteKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
