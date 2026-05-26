# Getting started — Kotlin

This guide explains how to generate Kotlin codecs for your
`@WireFormat` Swift types and use them from a Kotlin/JVM or
Kotlin/Android project.

> **Phase status.** The Gradle plugin that wraps the codegen CLI is
> planned for Phase 3 of the wirelet roadmap and is **not yet
> shipped**. Until it lands, invoke the codegen CLI manually as
> described below. The runtime API (`BinaryReader` / `BinaryWriter` /
> generated `*Codec` objects) is stable and will not change when the
> plugin ships — only the invocation site moves from a script into a
> Gradle DSL block.

## Prerequisites

- Swift 5.10+ available on the host that runs the codegen (you do not
  need Swift on the Kotlin consumer's machine; codegen is a build-time
  step).
- A checkout of wirelet at the version pinned by your Swift package.
- Kotlin 1.9+ in the consumer project.

## Generate codecs

The codegen entry point is the `emit-wirelet-kotlin` executable
shipped from the wirelet package:

```bash
swift run --package-path /path/to/wirelet emit-wirelet-kotlin \
    --source <swift-source-dir> \
    --output <kotlin-output-dir> \
    --include-package MySchema
```

Arguments:

- `--source` — directory containing the `.swift` files with
  `@WireFormat` / `@WireFormatEnum` / `@WireFormatChoice` declarations
  to scan. The emitter parses these with SwiftSyntax; it does not
  evaluate macros.
- `--output` — directory under which generated `*Codec.kt` files are
  written. Existing files in that directory are overwritten.
- `--include-package` — Kotlin package qualifier the generated files
  should land under. Repeat the flag (or pass a comma-separated list,
  depending on the build of the emitter you use) to scope codegen to
  a subset of types when sharing one source tree across multiple
  Kotlin modules.

A type whose Swift declaration carries
`@WireFormat(kotlin: .skip)` is excluded from emission;
`@WireFormat(kotlin: .explicit("com.example.foo.Bar"))` places its
codec at the explicit qualifier regardless of `--include-package`.

## Consume the generated codecs

The emitter produces a `<Type>Codec` Kotlin `object` per Swift type,
plus a `BinaryReader` / `BinaryWriter` pair the codecs depend on (the
runtime, vendored once per generation root).

```kotlin
import com.example.myschema.PointCodec
import io.github.jiyimeta.wirelet.BinaryReader
import io.github.jiyimeta.wirelet.BinaryWriter

// Decode bytes received over the wire from a Swift producer.
val bytes: ByteArray = receiveFromSwift()
val point = PointCodec.decode(BinaryReader(bytes))

// Encode bytes to send back.
val writer = BinaryWriter()
PointCodec.encode(point, writer)
val outgoing: ByteArray = writer.toByteArray()
```

The Kotlin model class (`data class Point(val x: Int, val y: Int)`)
is emitted alongside the codec — the same `.kt` file holds both,
so importing the codec brings the model into scope.

## Validation

A change to the wire spec (or to either of the Swift / Kotlin sides'
implementation of it) is caught by the cross-language conformance
suite under `kotlin/conformance-tests/`. The suite re-encodes a fixed
catalogue of values from Kotlin and compares byte-for-byte against
fixtures regenerated from Swift. If you ship a change to a generator,
regenerate the fixtures in the same commit; see
[wire-format-spec.md](wire-format-spec.md) for which kinds of changes
require fixture refreshes.

## Coming in Phase 3 — Gradle plugin

When the plugin lands, the manual `swift run …` invocation above will
be replaced with a Gradle DSL block in your module's `build.gradle.kts`:

```kotlin
// Illustrative — not yet shipped.
wirelet {
    swiftSources("../swift-package/Sources/MySchema")
    includePackages("MySchema")
    outputDir("$buildDir/generated/wirelet")
}
```

The generated sources will join the `kotlin/main` source set
automatically and the generation task will hook into `compileKotlin`.
The CHANGELOG will note the version that introduces it; until then,
wrap the `swift run` invocation in a `tasks.register("generateWirelet")
{ exec { … } }` block to keep the codegen step inside the Gradle build
graph.

## Next steps

- [wire-format-spec.md](wire-format-spec.md) — the byte layout your
  Kotlin codec is implementing.
- [schema-evolution.md](schema-evolution.md) — what's safe to change,
  what isn't.
- [getting-started-swift.md](getting-started-swift.md) — the producer
  side of the same wire format.
