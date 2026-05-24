// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "wirelet",
    platforms: [
        .macOS(.v14),
    ],
    products: [],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: []
)
