// swift-tools-version:6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "wirelet",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Wirelet", targets: ["Wirelet"]),
        .executable(name: "emit-wirelet-kotlin", targets: ["EmitWireletKotlin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .macro(
            name: "WireletMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Wirelet",
            dependencies: ["WireletMacros"]
        ),
        .target(
            name: "WireletSchema",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "WireletKotlinEmitter",
            dependencies: ["WireletSchema"]
        ),
        .executableTarget(
            name: "EmitWireletKotlin",
            dependencies: ["WireletSchema", "WireletKotlinEmitter"]
        ),
        .testTarget(
            name: "WireletRuntimeTests",
            dependencies: ["Wirelet"]
        ),
        .testTarget(
            name: "WireletMacrosTests",
            dependencies: [
                "WireletMacros",
                "Wirelet",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "WireletSchemaTests",
            dependencies: ["WireletSchema"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "WireletKotlinEmitterTests",
            dependencies: ["WireletKotlinEmitter", "WireletSchema"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "EmitWireletKotlinTests",
            dependencies: ["EmitWireletKotlin", "WireletKotlinEmitter", "WireletSchema"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
