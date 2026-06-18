// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SharedSchema",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SharedSchema", targets: ["SharedSchema"]),
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "SharedSchema",
            dependencies: [
                .product(name: "Wirelet", package: "swift-wirelet"),
            ],
        ),
    ],
)
