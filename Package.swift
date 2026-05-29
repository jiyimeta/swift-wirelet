// swift-tools-version:6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-wirelet",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Wirelet", targets: ["Wirelet"]),
        .library(name: "WireletObservable", targets: ["WireletObservable"]),
        .executable(name: "emit-wirelet-kotlin", targets: ["EmitWireletKotlin"]),
        .executable(name: "emit-wirelet-observable", targets: ["EmitWireletObservable"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
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
        .systemLibrary(
            name: "CWireletJNI",
            path: "Sources/CWireletJNI"
        ),
        .macro(
            name: "WireletObservableMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "WireletObservable",
            dependencies: [
                "Wirelet",
                "WireletObservableMacros",
                "CWireletJNI",
            ]
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
        .target(
            name: "WireletObservableSchema",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "WireletObservableKotlinEmitter",
            dependencies: [
                "WireletObservableSchema",
                "WireletKotlinEmitter",
            ]
        ),
        .executableTarget(
            name: "EmitWireletObservable",
            dependencies: [
                "WireletObservableSchema",
                "WireletObservableKotlinEmitter",
            ]
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
        .testTarget(
            name: "ConformanceTests",
            dependencies: ["Wirelet"]
        ),
        .testTarget(
            name: "WireletObservableTests",
            dependencies: ["WireletObservable", "Wirelet"]
        ),
        .testTarget(
            name: "WireletObservableMacrosTests",
            dependencies: [
                "WireletObservableMacros",
                "WireletObservable",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "WireletObservableSchemaTests",
            dependencies: ["WireletObservableSchema"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "WireletObservableKotlinEmitterTests",
            dependencies: [
                "WireletObservableKotlinEmitter",
                "WireletObservableSchema",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "EmitWireletObservableTests",
            dependencies: [
                "EmitWireletObservable",
                "WireletObservableKotlinEmitter",
                "WireletObservableSchema",
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
