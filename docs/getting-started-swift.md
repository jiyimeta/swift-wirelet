# Getting started — Swift

This guide takes you from zero to encoding and decoding a value with
the `@WireFormat` macro in a Swift Package Manager project.

## Install

Add wirelet as a dependency in your `Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/jiyimeta/wirelet.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "Wirelet", package: "wirelet"),
            ],
        ),
    ],
)
```

The `Wirelet` product re-exports the runtime types (`WireFormatWriter`,
`WireFormatReader`, `WireFormatError`, …) and exposes the macros
(`@WireFormat`, `@WireFormatField`, `@WireFormatEnum`,
`@WireFormatChoice`). No additional plugin configuration is needed —
the macros run inside SwiftPM's macro sandbox.

## Declare a type

Attach `@WireFormat` to a `struct` whose stored properties all
themselves conform to `WireFormat` (the built-in conformances on
`Int*`, `UInt*`, `Bool`, `Float`, `Double`, `String`, `Data`,
`Optional`, `Array`, `Dictionary` cover the common cases):

```swift
import Wirelet

@WireFormat
struct Point {
    var x: Int32
    var y: Int32
}
```

Implicit tags are assigned in declaration order: `x` → 1, `y` → 2.

To pin a tag explicitly — for example, when you intend to later
reorder fields without breaking the wire format — annotate the
property:

```swift
@WireFormat
struct Point {
    @WireFormatField(tag: 1) var x: Int32
    @WireFormatField(tag: 2) var y: Int32
}
```

## Encode and decode

The macro synthesizes `WireFormatEncodable` + `WireFormatDecodable`
conformance. Two convenience entry points sit on top of those
protocols:

```swift
let p = Point(x: 1, y: 2)
let data = p.encodeToData()        // returns Data

let q = try Point(decoding: data)  // throws WireFormatError on malformed input
```

For lower-level use (encoding many values into one buffer, or decoding
inside a larger record), reach for the protocol methods directly:

```swift
var writer = WireFormatWriter()
p.encode(into: &writer)
let bytes = writer.data

var reader = WireFormatReader(data: bytes)
let r = try Point(from: &reader)
```

## Enums and choices

Wrap a `CaseIterable & Equatable` enum with `@WireFormatEnum` for
discriminated tag values:

```swift
@WireFormatEnum
enum Channel: UInt8, CaseIterable, Equatable {
    case left, right, center
}
```

For a sum type with associated values, use `@WireFormatChoice`:

```swift
@WireFormatChoice
enum Payload {
    case text(String)
    case image(Data)
}
```

The case's declaration-order index (0, 1, 2, …) is the wire
discriminator. Adding a new case at the end of the enum is the only
wire-stable extension; see
[schema-evolution.md](schema-evolution.md) for the full table of
allowed changes.

## Next steps

- [wire-format-spec.md](wire-format-spec.md) — language-neutral binary
  specification.
- [schema-evolution.md](schema-evolution.md) — what's safe to change,
  what isn't.
- [getting-started-kotlin.md](getting-started-kotlin.md) — generate a
  matching Kotlin codec so the same bytes round-trip on Android / JVM.
