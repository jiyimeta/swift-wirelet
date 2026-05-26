# cross-roundtrip

End-to-end demo that one wirelet schema, declared once in Swift, can be
encoded by a Swift program and decoded by a JVM program using the
emitter-generated Kotlin codec — the same bytes round-trip cleanly
across the language boundary.

## Layout

```
cross-roundtrip/
├── kotlin-codegen.json                       emitter config (model + codec packages)
├── shared-schema/                            SwiftPM lib: @WireFormat Message struct
│   └── Sources/SharedSchema/Shared.swift
├── swift-encoder/                            SwiftPM executable: writes bytes
│   └── Sources/swift-encoder/main.swift
├── jvm-decoder/                              Kotlin/JVM Gradle module: reads bytes
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── gradle/wrapper/...                    Gradle 8.5 wrapper
│   ├── gradlew, gradlew.bat
│   └── src/main/kotlin/io/github/jiyimeta/wirelet/example/
│       ├── Main.kt                           entry point
│       └── model/Message.kt                  hand-authored data class
└── verify.sh                                 end-to-end driver
```

The Kotlin `MessageCodec.kt` is **generated** by `emit-wirelet-kotlin`
into `jvm-decoder/build/generated/wirelet/...` at build time — it is
not checked in. The matching `Message` data class is hand-authored
because the emitter today emits codecs only, not model types.

## Running

```
./verify.sh
```

Expected output (final line):

```
id=42 text=hello tags=[a, b]
```

## Modifying the schema

Edit `shared-schema/Sources/SharedSchema/Shared.swift`, update
`swift-encoder/Sources/swift-encoder/main.swift` to produce the new
payload, and update `jvm-decoder/.../Main.kt` (and
`jvm-decoder/.../model/Message.kt`) to match. Re-run `./verify.sh` —
the codegen step regenerates `MessageCodec.kt` from the new schema.
