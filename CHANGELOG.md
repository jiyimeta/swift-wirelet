# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is pre-1.0, minor versions may include breaking changes.

Published artifacts (Maven runtimes and the Gradle plugin) are released to
GitHub Packages; the SwiftPM package is consumed by Git revision/tag.

## [Unreleased]

## [0.5.0] - 2026-08-25

### Added

- A `@WireFormat` field's Swift default value is carried into the generated
  Kotlin `data class` as a parameter default. The wire format is append-only
  and its decoders skip tags they do not recognise, so appending a field keeps
  every existing *encoder* working — but the generated Kotlin gained a required
  constructor parameter each time, so the same append broke every Kotlin host
  at the source level. The two halves of the contract now agree: declare
  `public var showsLyrics: UInt8 = 1` and hosts that predate the field keep
  compiling, with the behaviour the default names.
  Deliberately per-field rather than blanket — a default belongs only where a
  safe value exists, and where none does the compile error is the point, since
  it forces each host to decide. Only plain literals of the scalar types the
  wire already carries are translated (`1` → `1u` for `UInt8`, `7` → `7L` for
  `Int64`, and so on); a default the emitter cannot vouch for fails codegen
  with `KotlinEmitterError.untranslatableDefault` rather than being dropped,
  because dropping it would restore the required parameter silently, in
  someone else's build. Optional fields are unchanged: their `null` comes from
  the type, and a declared default does not override it.

## [0.4.1] - 2026-08-14

### Changed

- `Wirelet` imports `FoundationEssentials` on platforms that ship it
  (Linux, Android, WASI) instead of the `Foundation` umbrella. The
  umbrella carries ICU, which costs ~10 MB brotli in a WebAssembly build
  for a module that only needs `Data`; measured in a consumer, a probe
  linking the codecs went from 13.65 MB to 3.55 MB. Apple platforms have
  no `FoundationEssentials` module and are unaffected. No API change.

## [0.4.0] - 2026-06-17

### Changed

- Migrated the JNI plumbing for the Android Observable and Provided
  bridges onto [`swift-java-jni-core`](https://github.com/swiftlang/swift-java-jni-core),
  replacing the hand-rolled `JObject` / `CWireletJNI` layer.

## [0.3.2] - 2026-06-02

### Added

- `[String]` (string-list) method-argument support across the Observable
  bridge, device-validated on a Pixel 8a.

## [0.3.1] - 2026-06-02

### Fixed

- Nested `@WireFormatEnum` field encoding in the Kotlin emitter.

## [0.3.0] - 2026-06-02

### Added

- Provided bridge (`@WireletProvided`): Swift calls into a
  Kotlin-implemented service over JNI, with a Swift proxy, a Kotlin
  interface/adapter, and constructor injection. Device-validated on a
  Pixel 8a.

## [0.2.2] - 2026-06-01

### Fixed

- iOS consumer fix (correct version metadata for downstream iOS graphs).

## [0.2.1] - 2026-06-01

### Fixed

- iOS platform declaration in the package manifest.

## [0.2.0] - 2026-05-31

### Added

- Observable bridge (`@WireletObservable` + `@Observable`): generates a
  Kotlin `ViewModel` exposing a `StateFlow` over JNI.

## [0.1.0-alpha.2] - 2026-05-26

### Changed

- Follow-up to the first alpha publish.

## [0.1.0-alpha.1] - 2026-05-26

### Added

- First published alpha: the `@WireFormat` macro toolkit (Swift runtime,
  macros, schema parser, Kotlin emitter CLI, and SwiftPM build-tool
  plugins) plus the cross-language conformance suite.

[Unreleased]: https://github.com/jiyimeta/swift-wirelet/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/jiyimeta/swift-wirelet/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.1.0-alpha.2...v0.2.0
[0.1.0-alpha.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/jiyimeta/swift-wirelet/releases/tag/v0.1.0-alpha.1
