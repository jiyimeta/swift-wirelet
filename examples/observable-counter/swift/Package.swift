// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ObservableCounterJNI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // `type: .dynamic` is required so the SwiftPM cross-build for
        // aarch64-unknown-linux-android24 produces libObservableCounterJNI.so
        // (vs an .a static archive that Android cannot dlopen).
        .library(
            name: "ObservableCounterJNI",
            type: .dynamic,
            targets: ["ObservableCounterJNI"]
        ),
    ],
    dependencies: [
        // Relative path from examples/observable-counter/swift/ up to repo root.
        .package(name: "swift-wirelet", path: "../../.."),
    ],
    targets: [
        .target(
            name: "ObservableCounterJNI",
            dependencies: [
                .product(name: "Wirelet", package: "swift-wirelet"),
                .product(name: "WireletObservable", package: "swift-wirelet"),
            ],
            plugins: [
                .plugin(name: "WireletObservableBridges", package: "swift-wirelet"),
            ]
        ),
    ]
)
