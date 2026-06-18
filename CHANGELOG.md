# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is pre-1.0, minor versions may include breaking changes.

Published artifacts (Maven runtimes and the Gradle plugin) are released to
GitHub Packages; the SwiftPM package is consumed by Git revision/tag.

## [Unreleased]

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

[Unreleased]: https://github.com/jiyimeta/swift-wirelet/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/jiyimeta/swift-wirelet/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/jiyimeta/swift-wirelet/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jiyimeta/swift-wirelet/compare/v0.1.0-alpha.2...v0.2.0
[0.1.0-alpha.2]: https://github.com/jiyimeta/swift-wirelet/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/jiyimeta/swift-wirelet/releases/tag/v0.1.0-alpha.1
