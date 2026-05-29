# `observable-counter` — end-to-end Wirelet Observable bridge demo

Mirrors `cross-roundtrip`'s shape, but exercises the Observable side of the
bridge end to end: a Swift `@WireletObservable @Observable` class crosses the
JNI boundary as an Android `ViewModel` whose `StateFlow` properties are
collected by Compose.

```
shared between Swift impl + Kotlin codegen
├── swift/                       SwiftPM package
│   ├── Package.swift            type: .dynamic → libObservableCounterJNI.so
│   └── Sources/ObservableCounterJNI/
│       ├── TodoItem.swift       @WireFormat struct
│       └── TodoListVM.swift     @WireletObservable @Observable class
├── android-app/                 standalone Gradle project
│   └── app/                     :app — Android module
└── build.sh                     publishToMavenLocal → cross-compile → assembleDebug
```

## One-shot verification

The script below boots no emulator; it assumes one is already running
(`emulator -avd <name>` in another shell). To run end to end from cold:

```bash
./examples/observable-counter/verify.sh
```

See [the Phase 4 implementation plan](../../docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md)
for the design rationale.
