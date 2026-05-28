# Wirelet Observable bridge — design

**Status**: Spec (brainstorming complete, awaiting plan)
**Date**: 2026-05-29
**Author**: Kiichi Ito (with Claude)

## Purpose

Extend `swift-wirelet` so a Swift `@Observable` class can cross the Swift ↔ Kotlin JNI boundary as a Kotlin `androidx.lifecycle.ViewModel` whose stored properties are exposed as `StateFlow`. The hand-written JNI plumbing — per-property `withObservationTracking` traps on the Swift side and `MutableStateFlow` re-arming on the Kotlin side — is generated from a single Swift source-of-truth declaration.

This is the second capability under the `wirelet` umbrella, after the existing `@WireFormat` TLV codec family. Together they let `wirelet` fill the gaps that `swift-java`'s `jextract` leaves unaddressed for cross-runtime IPC: jextract bridges callable Swift surface area, `@WireFormat` bridges value-type wire bytes, and `@WireletObservable` bridges live observable state.

## Background

### `swift-java` jextract scope

`swift-java` 0.3.0 jextract reflects Swift classes into Java/Kotlin as opaque pointer wrappers with method and property accessors. It has zero special handling for `@Observable`: properties of an `@Observable` class are bridged as plain `get<Name>()` / `set<Name>(value)` methods, losing the reactive contract entirely. A Kotlin consumer cannot observe Swift-side mutations without polling.

### swift4j prior art

`scade-platform/swift4j` already implements this exact pattern, but tied to a different toolchain. Key shape:

- Per-stored-property, swift4j emits a Swift JNI bridge `<prop>_get_with_observation_tracking_jni(onChange:)` that wraps the property read in `withObservationTracking { … } onChange: { onChange.call("run") }`. The `onChange` is a `JObject` wrapping a Java `Runnable`.
- A Kotlin CLI emits one `<Name>ViewModel : androidx.lifecycle.ViewModel` per `@Observable` Swift class. Per stored property:

    ```kotlin
    private val _foo = MutableStateFlow(readFooWithTracking())
    val foo: StateFlow<Foo> = _foo.asStateFlow()
    private fun readFooWithTracking(): Foo = nativeFooTrack(self) {
        viewModelScope.launch(Dispatchers.Main) { _foo.value = readFooWithTracking() }
    }
    ```

  Re-arm is recursive because Swift Observation fires `onChange` exactly once per access; re-reading inside the callback re-subscribes.

- `@ObservationIgnored` is honored. Computed properties are included if they read other observable storage.

We adopt the same overall pattern but tighten the contract: explicit opt-in via `@WireletObservable`, generation guarded by `#if os(Android)` so Apple builds stay clean, value-type properties marshaled through the existing `@WireFormat` TLV codecs, and the Kotlin runtime split as a separate Maven artifact so wire-format-only consumers do not pay the coroutines + AndroidX cost.

## Goal

After this work:

- A Swift `@Observable` class decorated with `@WireletObservable` produces, on the Android compile, a set of `@_cdecl` JNI bridges for each stored property (read-with-tracking + setter where mutable) and any opted-in method.
- The `emit-wirelet-observable` CLI scans `@WireletObservable` declarations in the consumer's Swift sources and emits a `<Name>ViewModel.kt` per class, derived from `androidx.lifecycle.ViewModel`, with one `StateFlow<T>` per stored property and wired-in re-arm.
- Value-type properties typed as `@WireFormat` structs/enums marshal through the existing TLV codec; primitive types (`Int32`, `Int64`, `Bool`, `Float`, `Double`, `String`) take direct JNI fast paths.
- A `wirelet-observable-runtime` Maven artifact ships the AndroidX `ViewModel` base helpers and the `Runnable`-callback JNI helpers; the existing `wirelet-runtime` artifact remains coroutines-free.
- Apple builds (iOS / macOS / Xcode) compile the same Swift source with the same `@WireletObservable` macro applied, but produce no JNI symbols — only the underlying `@Observable` class is exposed.

## Non-goals

- **Bidirectional observation.** Kotlin → Swift Flow consumption is not in scope. Observation flows one way: Swift state → Kotlin StateFlow.
- **Pure-KMP / desktop / server-side Kotlin support.** v0.1 targets AndroidX `ViewModel` directly. Splitting into a `wirelet-observable-core` + `wirelet-observable-androidx` adapter pair is a Phase ≥ 6 refactor (not in this spec).
- **Nested `@Observable` deep flattening.** Mutations inside a nested observable do not propagate to the parent's StateFlow. Consumers either model the nested type as a separate `@WireletObservable` (exposed as its own ViewModel) or restructure to put observable state at the top level.
- **Computed property tracking polish.** Computed properties are included in generation but their behavior matches Apple's Observation contract: they fire onChange only when they read other tracked storage. No diagnostics warn about computed properties that never fire.
- **Diff-based array updates.** Each `MutableStateFlow<List<T>>` update re-encodes the full array. Incremental / append-only optimization is deferred.
- **Generic `@Observable` classes.** v0.1 supports only concrete (non-generic) class declarations. Generic class support is deferred indefinitely (matches the existing `@WireFormat` constraint).

## Scope

In:

- New Swift package targets: `WireletObservable` (runtime), `WireletObservableMacros` (macro impl), `WireletObservableSchema` (schema parser), `WireletObservableKotlinEmitter` (Kotlin generator), `EmitWireletObservable` (CLI binary).
- New Swift module: `CWireletJNI` — system module wrapping JNI types (`JNIEnv`, `jlong`, `jobject`, `jbyteArray`, etc.) for use on Android. Re-exported by `WireletObservable` under `#if os(Android)`.
- New Kotlin Gradle module: `kotlin/observable-runtime/` → `wirelet-observable-runtime` Maven artifact.
- Existing `kotlin/gradle-plugin/` extended with an `observable` source-set DSL and a `generateWireletObservableViewModels` task.
- New example: `examples/observable-counter/` — minimal Android Compose app with one Swift `@WireletObservable` VM containing primitives, a `String`, a `[TodoItem]` array, and one custom `@WireFormat` struct (`TodoItem`).
- Unit tests for each new module and an Android instrumentation / integration smoke that exercises the example.

Out:

- Apple-side example app (the existing wirelet examples cover Swift-only usage; the observable surface is meaningful only with a JNI counterpart).
- Maven artifact rename or Group ID changes. Coordinates: `io.github.jiyimeta:wirelet-observable-runtime` matches the existing `io.github.jiyimeta:wirelet-runtime` naming.

## Architecture overview

```
                  ┌────────────────────────────────────┐
                  │   @WireletObservable               │
                  │   @Observable                      │
                  │   final class FooVM (Swift)        │
                  └──────────────────┬─────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
        ┌───────────────────────┐         ┌──────────────────────────┐
        │ Swift macro           │         │ emit-wirelet-observable  │
        │ (compile-time)        │         │ (SwiftSyntax CLI, new)   │
        │                       │         │                          │
        │ for each var x:       │         │ → <Foo>ViewModel.kt      │
        │   #if os(Android)     │         │   : androidx.ViewModel   │
        │   __x_track_jni       │         │   _x: MutableStateFlow   │
        │   #endif              │         │                          │
        └───────────┬───────────┘         └──────────────┬───────────┘
                    │                                    │
                    ▼                                    ▼
        ┌───────────────────────┐         ┌──────────────────────────┐
        │ WireletObservable     │         │ wirelet-observable-      │
        │  + @_exported import  │         │ runtime (Maven artifact) │
        │    CWireletJNI on     │         │ AndroidX ViewModel base, │
        │    Android            │         │ kotlinx.coroutines,      │
        │  + Runnable JObject   │         │ JNI Runnable callbacks   │
        │    helper             │         │                          │
        └───────────────────────┘         └──────────────────────────┘
```

## Annotation surface

Swift consumers write:

```swift
import Wirelet              // existing — @WireFormat etc.
import WireletObservable    // new
import Observation

@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool
}

@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0

    public init() {}

    @WireletExpose
    public func add(_ item: TodoItem) {
        items.append(item)
        totalCount += 1
    }

    @WireletExpose
    public func clear() {
        items.removeAll()
        totalCount = 0
    }
}
```

Rules:

- `@WireletObservable` must be paired with `@Observable`. Macro emits a diagnostic if `@Observable` is absent (and does not synthesize it — the consumer's relationship with Apple's Observation framework remains explicit).
- The class must be `final`. Subclassable observable VMs are not supported in v0.1 (matches Apple's recommendation for `@Observable` types).
- Stored property types must be one of: primitive (`Int8/16/32/64`, `UInt8/16/32/64`, `Bool`, `Float`, `Double`, `String`), `@WireFormat` struct/enum, or `Array` / `Optional` of the above. Other types raise a macro diagnostic.
- `@ObservationIgnored` properties are skipped.
- Methods are not bridged automatically. To expose a method, annotate it with `@WireletExpose`. (Method bridging is a thin wrapper around jextract's existing capability; we adopt the marker to keep the surface explicit and the JNI symbol table small.)

## Macro expansion contract

`@WireletObservable` is an extension macro that adds the JNI bridges as an extension on the annotated class. All generated code is wrapped in `#if os(Android) … #endif`. The macro itself does not branch on the compile target — it always emits the guarded block, and the guard decides whether the bridges compile.

For the `TodoListVM` above, macro expansion (simplified) produces:

```swift
extension TodoListVM {
    #if os(Android)
    @_cdecl("WireletObservable_TodoListVM_items_track")
    public static func __items_track_jni(
        _ env: UnsafeMutablePointer<JNIEnv>?,
        _ self_ptr: jlong,
        _ on_change: jobject?
    ) -> jbyteArray? {
        let me = WireletObservableJNI.unwrap(self_ptr) as TodoListVM
        let runnable = JObject(env: env, jobject: on_change)
        var snapshot: [TodoItem] = []
        withObservationTracking {
            snapshot = me.items
        } onChange: {
            runnable.call(method: "run")
        }
        return WireletObservableJNI.encodeArray(env: env, snapshot)
    }

    @_cdecl("WireletObservable_TodoListVM_filter_track")
    public static func __filter_track_jni(
        _ env: UnsafeMutablePointer<JNIEnv>?,
        _ self_ptr: jlong,
        _ on_change: jobject?
    ) -> jstring? { /* … */ }

    @_cdecl("WireletObservable_TodoListVM_totalCount_track")
    public static func __totalCount_track_jni(
        _ env: UnsafeMutablePointer<JNIEnv>?,
        _ self_ptr: jlong,
        _ on_change: jobject?
    ) -> jint { /* … */ }

    // Setters for mutable properties + ctor / release entrypoints
    @_cdecl("WireletObservable_TodoListVM_new")
    public static func __new_jni(_ env: UnsafeMutablePointer<JNIEnv>?) -> jlong { /* … */ }

    @_cdecl("WireletObservable_TodoListVM_release")
    public static func __release_jni(
        _ env: UnsafeMutablePointer<JNIEnv>?,
        _ self_ptr: jlong
    ) { /* … */ }
    #endif
}
```

JNI types (`JNIEnv`, `jlong`, `jobject`, `jbyteArray`, `jstring`, `jint`) are provided by `CWireletJNI`, re-exported transitively by `WireletObservable` under the same `#if os(Android)` guard. The consumer's source needs only `import WireletObservable`.

Marshaling rules per property type:

| Swift property type | JNI return type | Notes |
|---|---|---|
| `Int8/16/32`, `UInt8/16` | `jint` | Truncating/zero-extending cast |
| `Int64`, `UInt32/64` | `jlong` | UInt64 → jlong reinterpret |
| `Bool` | `jboolean` | |
| `Float` | `jfloat` | |
| `Double` | `jdouble` | |
| `String` | `jstring?` | UTF-8 → Java modified UTF-8 via JNI `NewStringUTF` |
| `Optional<T>` | T's JNI type | Reference types: `nil` → `nil`. Value types: 1-byte presence prefix encoded as `jbyteArray` |
| `Data` / `[UInt8]` | `jbyteArray?` | Raw bytes |
| `[T]` where `T: WireFormat` | `jbyteArray?` | Length-prefixed varint count + concatenated TLV |
| `[T]` where `T` primitive | `jbyteArray?` | TLV-style; Kotlin side decodes to `List<T>` |
| `T: WireFormat` | `jbyteArray?` | Existing `T.encodeToData()` |

The `__release` entrypoint frees the Swift-side strong reference held by the `jlong` pointer. The Kotlin `ViewModel.onCleared()` calls into it.

## Kotlin codegen contract

The `emit-wirelet-observable` CLI:

- Accepts the same `--schema` source paths as `emit-wirelet-kotlin`.
- Scans for class declarations with both `@WireletObservable` and `@Observable` attributes; ignores any other declarations (handing them off implicitly to the existing wireformat emitter when run as part of the same Gradle task graph).
- Emits one `<Name>ViewModel.kt` per matching class.

Generated file shape (for `TodoListVM`):

```kotlin
package io.github.jiyimeta.observablecounter.generated

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.github.jiyimeta.observablecounter.TodoItem
import io.github.jiyimeta.observablecounter.codecs.TodoItemCodec
import io.github.jiyimeta.wirelet.observable.WireletList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class TodoListVMViewModel internal constructor(
    private val nativePtr: Long
) : ViewModel() {

    private val _items = MutableStateFlow(readItemsWithTracking())
    val items: StateFlow<List<TodoItem>> = _items.asStateFlow()

    private val _filter = MutableStateFlow(readFilterWithTracking())
    val filter: StateFlow<String> = _filter.asStateFlow()

    private val _totalCount = MutableStateFlow(readTotalCountWithTracking())
    val totalCount: StateFlow<Int> = _totalCount.asStateFlow()

    fun add(item: TodoItem) =
        nativeAdd(nativePtr, TodoItemCodec.encode(item))

    fun clear() = nativeClear(nativePtr)

    private fun readItemsWithTracking(): List<TodoItem> {
        val bytes = nativeItemsTrack(nativePtr, Runnable {
            viewModelScope.launch(Dispatchers.Main) {
                _items.value = readItemsWithTracking()
            }
        })
        return WireletList.decode(bytes, TodoItemCodec)
    }

    private fun readFilterWithTracking(): String =
        nativeFilterTrack(nativePtr, Runnable {
            viewModelScope.launch(Dispatchers.Main) {
                _filter.value = readFilterWithTracking()
            }
        })

    private fun readTotalCountWithTracking(): Int =
        nativeTotalCountTrack(nativePtr, Runnable {
            viewModelScope.launch(Dispatchers.Main) {
                _totalCount.value = readTotalCountWithTracking()
            }
        })

    override fun onCleared() {
        nativeRelease(nativePtr)
        super.onCleared()
    }

    private external fun nativeItemsTrack(self: Long, onChange: Runnable): ByteArray
    private external fun nativeFilterTrack(self: Long, onChange: Runnable): String
    private external fun nativeTotalCountTrack(self: Long, onChange: Runnable): Int
    private external fun nativeAdd(self: Long, itemBytes: ByteArray)
    private external fun nativeClear(self: Long)
    private external fun nativeRelease(self: Long)

    companion object {
        init { System.loadLibrary("ObservableCounterJNI") }

        fun create(): TodoListVMViewModel =
            TodoListVMViewModel(nativeNew())

        @JvmStatic
        private external fun nativeNew(): Long
    }
}
```

Notes:

- `List<TodoItem>` is the Kotlin-side mapping for Swift `Array<TodoItem>`. `List` is the idiomatic immutable interface; `MutableStateFlow<List<T>>.equals` performs element-wise deep equality, which dedups identical re-encodings.
- `WireletList.decode(bytes, TodoItemCodec)` is a small helper from `wirelet-observable-runtime` that reads the length prefix + count + concatenated TLV form. It mirrors the existing emit-wirelet-kotlin TLV array decoding.
- `external fun` symbol names follow the macro-side `@_cdecl` registration (`WireletObservable_<Class>_<Member>`).
- The Kotlin file does not name `JNIEnv` or any JNI type. All JNI signatures are at the Kotlin language level.

## Runtime contracts

### Swift side: `WireletObservable` module

```swift
// Sources/WireletObservable/WireletObservable.swift
#if os(Android)
@_exported import CWireletJNI
#endif

public enum WireletObservableJNI {
    #if os(Android)
    public static func unwrap<T: AnyObject>(_ ptr: jlong) -> T { /* … */ }
    public static func retain<T: AnyObject>(_ value: T) -> jlong { /* … */ }
    public static func release(_ ptr: jlong) { /* … */ }
    public static func encodeArray<T: WireFormat>(env: ..., _ array: [T]) -> jbyteArray? { /* … */ }
    public static func decodeArray<T: WireFormat>(env: ..., _ bytes: jbyteArray?) throws -> [T] { /* … */ }
    #endif
}

#if os(Android)
public final class JObject {
    private let env: UnsafeMutablePointer<JNIEnv>
    private let obj: jobject
    public init(env: ..., jobject: ...) { /* … */ }
    public func call(method: String) { /* … */ }
    deinit { /* DeleteGlobalRef */ }
}
#endif
```

The macro-generated extensions reference only types declared inside the `#if os(Android)` block. On Apple, the entire module body skips that block; the macro-generated bridges, also guarded, similarly skip.

### Kotlin side: `wirelet-observable-runtime`

Minimal surface:

- `WireletList.decode(bytes: ByteArray, codec: WireletCodec<T>): List<T>` — counterpart to the Kotlin emitter's existing array decoding.
- A `JObjectGlobalRef` helper invoked from JNI Swift code via `NewGlobalRef` / `DeleteGlobalRef` ceremony. The Kotlin runtime side provides a `Runnable` wrapper that holds the strong ref.

Dependencies: `androidx.lifecycle:lifecycle-viewmodel` + `org.jetbrains.kotlinx:kotlinx-coroutines-android`. These transitively pull `kotlinx-coroutines-core`.

## Re-arm semantics and edge cases

Swift `withObservationTracking { read } onChange: { … }` fires `onChange` exactly once for any tracked mutation; the read inside the closure is the access that registers the subscription. After `onChange` runs, the subscription is dead.

The generated Kotlin path re-arms by calling the same `nativeXxxTrack(self, runnable)` again inside `viewModelScope.launch(Dispatchers.Main) { _x.value = readXxxWithTracking() }`. The recursive call enters Swift, registers a fresh tracker, returns the (possibly already-changed) current value, and the new subscription is live by the time we return.

Edge cases:

- **Burst mutations.** If two `count += 1` calls happen before the Kotlin re-arm executes, the first fires `onChange`, the second changes the value but its `onChange` has no live subscription. The re-arm reads the *current* value via `withObservationTracking`, so the new value is captured. The `MutableStateFlow` updates skip any intermediate state. This is acceptable — the contract is "eventual consistency, last-write-wins on each re-arm tick", matching swift4j.
- **`Dispatchers.Main` re-entrancy.** If the consumer mutates from the main thread inside a Flow `collect`, the re-arm coroutine is dispatched but not synchronously invoked. The next event loop tick runs it.
- **VM destruction during in-flight callback.** If `onCleared()` runs while a `Runnable` is queued, the JNI side `__release` frees the Swift pointer; a subsequent re-arm call would call into a freed object. Mitigation: the macro-generated `__release` zeroes the slot; track-bridges check for the sentinel and no-op when called against a freed slot. The Kotlin side also cancels `viewModelScope`, so queued re-arms are cancelled before dispatch in practice.
- **Equality dedup across JNI copies.** `MutableStateFlow.compareAndSet` uses `==`. Strings and primitives `==` naturally. `List<T>.equals` walks elements; `TodoItem` is a Kotlin data class generated by `WireletKotlinEmitter` with structural `equals`. So a re-encoded-then-decoded value that is byte-equal to the previous decodes to an `equals`-equal new instance and is deduped.

## Gradle plugin integration

The existing `io.github.jiyimeta.wirelet` plugin gains an `observable` block in its DSL:

```kotlin
plugins {
    id("io.github.jiyimeta.wirelet") version "0.2.0"
}

dependencies {
    implementation("io.github.jiyimeta:wirelet-runtime:0.2.0")
    implementation("io.github.jiyimeta:wirelet-observable-runtime:0.2.0")
}

wirelet {
    sources {
        register("main") {
            schemaPaths.from(file("../shared-schema/Sources"))
            packageName.set("com.example.app.codecs")
            includePackages.add("MyApp")
        }
    }
    observable {
        register("main") {
            schemaPaths.from(file("../shared-schema/Sources"))
            packageName.set("com.example.app.viewmodels")
            includePackages.add("MyApp")
        }
    }
}
```

Behavior:

- A new `generateWireletObservableViewModels<SourceSet>` task forks the `emit-wirelet-observable` CLI.
- Output rooted at `${buildDir}/generated/wirelet/observable/${sourceSetName}/kotlin/` and added to the corresponding source set's `srcDirs`.
- `compile{Variant}Kotlin` is `dependsOn` both the existing `generateWireletCodecs` and the new `generateWireletObservableViewModels`.
- If the consumer registers a wireformat source set and an observable source set with the same schema paths, the two CLIs operate on the same input independently; output paths are disjoint so neither overwrites the other.

## Example: `examples/observable-counter/`

Layout:

```
examples/observable-counter/
├── shared-schema/
│   └── Sources/
│       └── ObservableCounterModel/
│           ├── TodoItem.swift             # @WireFormat
│           └── TodoListVM.swift           # @WireletObservable @Observable
├── swift-impl/                            # Swift package built into libObservableCounterJNI.so
│   ├── Package.swift
│   └── Sources/
│       └── ObservableCounterJNI/          # Imports shared-schema; macros expand on Android compile
├── android-app/                           # Compose UI consuming the generated ViewModel
│   ├── build.gradle.kts                   # applies io.github.jiyimeta.wirelet
│   ├── settings.gradle.kts
│   └── app/
│       └── src/main/
│           ├── AndroidManifest.xml
│           ├── java/com/example/observablecounter/MainActivity.kt
│           └── jniLibs/                   # populated by build.sh
└── build.sh                               # cross-compile Swift → .so, then ./gradlew assembleDebug
```

Compose UI (illustrative):

```kotlin
@Composable
fun TodoScreen(vm: TodoListVMViewModel = viewModel(factory = TodoListVMViewModelFactory)) {
    val items by vm.items.collectAsStateWithLifecycle()
    val total by vm.totalCount.collectAsStateWithLifecycle()
    Column {
        Text("total=$total")
        items.forEach { item ->
            Row { Checkbox(checked = item.done, onCheckedChange = null); Text(item.title) }
        }
        Button(onClick = {
            vm.add(TodoItem(id = total + 1, title = "task #${total + 1}", done = false))
        }) { Text("Add") }
        Button(onClick = vm::clear) { Text("Clear") }
    }
}
```

Verification:

- Build the Swift target for `aarch64-unknown-linux-android28`, produce `libObservableCounterJNI.so`, drop into `app/src/main/jniLibs/arm64-v8a/`.
- `./gradlew assembleDebug` regenerates ViewModels via the plugin and compiles.
- Install + launch in an emulator (API 28+, arm64), tap Add repeatedly, observe the list and `total` update in lockstep with each tap.

## Testing strategy

| Layer | Location | Coverage |
|---|---|---|
| Swift macro | `Tests/WireletObservableMacrosTests` | Expansion snapshots via `SwiftSyntaxMacrosTestSupport`. Cover: primitives, String, Optional, Array of primitive, Array of `@WireFormat`, `@ObservationIgnored`, missing `@Observable` diagnostic, non-`final` class diagnostic. |
| Swift runtime | `Tests/WireletObservableTests` | The Apple build compiles `JObject` / `WireletObservableJNI` to nothing — verify by inspecting `swift build` symbol output on macOS. |
| Schema parser | `Tests/WireletObservableSchemaTests` | Parse multi-class files; recognize both `@WireletObservable` and `@Observable`; assert that classes missing `@Observable` are surfaced as a parser-level warning. |
| Kotlin emitter | `Tests/WireletObservableKotlinEmitterTests` | Golden-file comparison of `<Name>ViewModel.kt` for the `TodoListVM` shape and a primitive-only counter. Updates require committed fixture bump. |
| CLI | `Tests/EmitWireletObservableTests` | End-to-end: schema-paths in, generated `.kt` files on disk; covers the same shapes as the emitter tests but through the CLI argv path. |
| Kotlin runtime | `kotlin/observable-runtime/src/test/` | `WireletList.decode` round-trip, `JObjectGlobalRef` lifecycle stub (no live JNI; manual `Runnable` wrapper). |
| Gradle plugin | `kotlin/gradle-plugin/src/functionalTest/` | TestKit: registering an `observable` source set produces a `generateWireletObservableViewModels<Name>` task; output is added to `srcDirs`; incremental rebuild caches correctly. |
| Conformance | `kotlin/conformance-tests/` | A new fixture `observable_burst_v1.txt` records the sequence "create VM → add 10 items → observe 10 final-state Flow emissions" as a deterministic script the Android side runs in instrumentation. Drift in the re-arm contract fails the suite. |
| Cross | `examples/observable-counter/build.sh` | The example is built and smoke-tested in CI under the existing `examples.yml` workflow (extending the matrix to include an Android emulator job). |

## CI / publish

The existing `swift.yml`, `kotlin.yml`, `conformance.yml`, `examples.yml`, `publish.yml` are extended:

- `swift.yml` builds the new Swift targets (`WireletObservable`, `WireletObservableMacros`, `WireletObservableSchema`, `WireletObservableKotlinEmitter`, `EmitWireletObservable`) and runs their tests on macOS and Linux.
- `kotlin.yml` adds `kotlin/observable-runtime/` to the Gradle build and runs its unit tests.
- `examples.yml` cross-compiles the `observable-counter` Swift target for `aarch64-unknown-linux-android28` and `assembleDebug`s the Android app. A new emulator job (API 30 arm64) installs the APK and runs the instrumented smoke.
- `publish.yml` (tag-triggered) publishes `wirelet-observable-runtime` as an additional Maven artifact under the same Group ID. Version bumps in lockstep with `wirelet-runtime`.

The next public release tag after this work is `v0.2.0` (minor bump — additive, source-compatible).

## Phasing

Six phases, each ending in a working / committable state.

### Phase 1 — Swift runtime scaffolding

- Add `CWireletJNI` system module (header listing JNI types; matches swift-sheet-music's existing `CJNI`).
- Add `Sources/WireletObservable/` runtime target with `@_exported import CWireletJNI` under `#if os(Android)`, plus `WireletObservableJNI` helpers and `JObject`.
- Apple build passes (target contains nothing under Apple).
- Linux build passes (target also contains nothing — `CWireletJNI` is Android-only).
- No macro or codegen yet.

### Phase 2 — Macro

- Add `Sources/WireletObservableMacros/` with `@WireletObservable` extension-macro implementation.
- Macro expansion snapshot tests cover the primitive / String / `[T]` / Optional / `@WireFormat`-struct / `@ObservationIgnored` paths plus diagnostics.
- A minimal Android-side smoke (just the Swift compile + `.so` link, no Kotlin yet) verifies the generated `@_cdecl` symbols actually appear in the linked library.

### Phase 3 — Schema parser + Kotlin emitter + CLI

- Add `WireletObservableSchema`, `WireletObservableKotlinEmitter`, `EmitWireletObservable`.
- Golden-file tests for the `TodoListVM` shape.
- CLI integration test that writes generated `.kt` to a temp directory.

### Phase 4 — Kotlin runtime + Gradle plugin

- Add `kotlin/observable-runtime/` Gradle module → `wirelet-observable-runtime` artifact (unpublished local build first).
- Extend `kotlin/gradle-plugin/` with the `observable` DSL block and the `generateWireletObservableViewModels` task.
- Gradle TestKit functional tests.

### Phase 5 — `observable-counter` example

- Build the example end-to-end on a real Android emulator. Verify Flow emissions in instrumentation tests.
- Wire CI emulator job.

### Phase 6 — Publish

- README updated with an "Observable bridge" section pointing at the example.
- `v0.2.0` cut with both `wirelet-runtime` and `wirelet-observable-runtime` artifacts.
- swift-sheet-music's `Package.swift` revision pin bumped (separate PR there, not in this repo).

## Open questions / deferred items

- **Method bridging beyond `@WireletExpose`.** Should mutating methods that already cross via Apple's Observation contract auto-expose, or stay marker-gated? v0.1 marker-gated for explicitness; revisit after consumer feedback from swift-sheet-music's PlaybackEngine rebridge.
- **Diff-based `List<T>` updates.** For VMs with large arrays (e.g. sheet music's measure list), re-encoding on every change is expensive. A future `WireletListDiff` codec emitting `(insertions, deletions, modifications)` events lets the Kotlin side patch a `MutableStateFlow<List<T>>` incrementally. Deferred to v0.3 at earliest.
- **Pure-KMP runtime.** If desktop / server-side Kotlin consumers materialize, factor `wirelet-observable-core` (no AndroidX) out of `wirelet-observable-runtime` and ship `wirelet-observable-androidx` as the adapter. Surface choice depends on real consumer demand; not designed-for now.
- **`@WireletObservable` on actor types.** Apple's Observation does not yet integrate with actor isolation. Out of scope.
- **Nested `@WireletObservable`-of-`@WireletObservable`.** Could be supported by emitting a `StateFlow<ChildViewModel>` on the parent. Not implemented in v0.1 because the lifecycle ownership story is unclear (does the parent's `onCleared` also release the child's JNI ptr?).
