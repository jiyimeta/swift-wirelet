// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swift-encoder",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../shared-schema"),
    ],
    targets: [
        .executableTarget(
            name: "swift-encoder",
            dependencies: [
                .product(name: "SharedSchema", package: "shared-schema"),
            ],
        ),
    ],
)
