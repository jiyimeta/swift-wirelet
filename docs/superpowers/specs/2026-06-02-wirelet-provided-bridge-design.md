# Wirelet Provided bridge — design

**Status**: Spec (brainstorming complete, awaiting plan)
**Date**: 2026-06-02
**Author**: Kiichi Ito (with Claude)

## Purpose

Add a fourth `wirelet` capability, `@WireletProvided`, that lets **Swift code
(running in an Android `.so`) call into a Kotlin-implemented protocol**. A Swift
`protocol` is declared with `@WireletProvided`; its *implementation* (conformance)
is supplied on the Kotlin side. Swift invokes it across JNI, with value-typed
arguments and return values marshaled through the existing `@WireFormat` TLV
codecs.

This is the **mirror image** of `@WireletObservable` (which exposes live Swift
state to Kotlin) and the **dual** of `@WireletExpose` (Kotlin → Swift method
calls). It fills the one remaining quadrant of cross-runtime IPC that `wirelet`
does not yet cover.

## Motivation

The driving use case is building a **Swift-spine Android app** — the bulk of the
logic and much of the infrastructure is Swift, while the UI and a few platform
adapters are Kotlin. The concrete first consumer is the Folino Library feature:
a reactive Swift store (`@WireletObservable`) that depends on a **Kotlin-implemented
persistence service** (Room / DataStore). The Swift store hydrates from the store
on construction and writes through it on each mutation.

Without this capability, every Swift → Kotlin dependency has to be inverted: the
Kotlin layer becomes the composition root and the Swift object is demoted to a
stateless helper. That does not scale to a Swift-spine app where Kotlin
implements *select* infrastructure behind interfaces the Swift side owns.

### Where this sits in the wirelet capability set

| What is bridged | Owner | Direction |
| --- | --- | --- |
| Callable **Swift** surface | jextract / `@WireletExpose` | Kotlin → Swift |
| Value-type wire bytes | `@WireFormat` (TLV codec) | both directions (exists) |
| Live observable state | `@WireletObservable` | Swift state → Kotlin StateFlow |
| **Callable Kotlin surface (a provided protocol)** | **`@WireletProvided`** ← new | **Swift → Kotlin** |

The value-marshaling substrate (`@WireFormat` TLV codecs, already bidirectional
in both Swift and Kotlin) and the raw-JNI substrate (`CWireletJNI`, plus the
`JObject` global-ref wrapper) already exist. This capability assembles them in
the missing direction.

## Background — what already exists (the template to mirror)

The new capability mirrors the `@WireletObservable` machinery. Relevant existing
pieces:

- **`JObject`** — `Sources/WireletObservable/JObject.swift`. Wraps a local
  `jobject` as a JNI global ref, stores the `JavaVM`, and can invoke a Java
  method from Swift: `init?(env:, jobject:)` + `call(method: "run")`. Today it
  supports exactly one shape — **no-argument, `void` return** — used to fire the
  `Runnable` that re-arms a `StateFlow`. **This is the one existing Swift → Kotlin
  call and the seed we generalize.**
- **`CWireletJNI`** — `Sources/CWireletJNI/shim.h`. Exposes raw `<jni.h>` to
  Swift (`JNIEnv`, `JavaVM`, `jobject`, `jbyteArray`, `jstring`, primitives) and
  thereby the standard JNI calls: `GetObjectClass`, `GetMethodID`,
  `CallVoidMethodA` / `CallObjectMethodA` / `Call<Primitive>MethodA`,
  `NewByteArray` / `SetByteArrayRegion` / `GetByteArrayRegion` /
  `GetArrayLength`, `NewStringUTF` / `GetStringUTFChars`, `NewGlobalRef` /
  `DeleteGlobalRef`, `AttachCurrentThread`, `ExceptionCheck` / `ExceptionClear`.
- **`@WireFormat` TLV codecs** — `Sources/Wirelet` (`WireFormatWriter` /
  `WireFormatReader`) on Swift; `kotlin/runtime` (`BinaryWriter` / `BinaryReader`)
  on Kotlin; array/optional helpers in `kotlin/observable-runtime`
  (`WireletList`, `WireletOptional`). Both directions already work.
- **Observable Swift-bridge emitter** — `Sources/WireletObservableSwiftBridgesEmitter`
  emits the `@_cdecl` JNI bridges (`InvokeBridgeEmitter`, `TrackBridgeEmitter`),
  with argument classification in
  `Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift`.
- **Observable Kotlin emitter** — `Sources/WireletObservableKotlinEmitter`
  (`ViewModelEmitter`, `ObservableKotlinTypeMap`) + the `EmitWireletObservable`
  CLI, driven by the Gradle plugin (`kotlin/gradle-plugin`,
  `observable { register("main") { … } }` DSL + `GenerateWireletObservableViewModels`
  task, which forks `swift run … emit-wirelet-observable` and writes the
  `.wirelet-observable-jni.json` sidecar).
- **Example** — `examples/observable-counter/{swift,android-app}`: a single
  `@WireletObservable` `TodoListVM` (primitives, `String`, `[TodoItem]`, one
  `@WireFormat` `TodoItem`) with a Compose UI. Self-contained; the VM has no
  external dependency today — an ideal host for adding a DI scenario.

## Goal

After this work:

- A Swift `protocol` annotated `@WireletProvided` produces, on the Android
  compile, a generated Swift **proxy** type conforming to that protocol. Each
  method forwards across JNI to a Kotlin implementation: arguments encoded
  (primitive fast-path or `@WireFormat` TLV), the Kotlin method invoked via
  `Call*MethodA`, the return value decoded back.
- A matching **Kotlin interface** is generated for the app to implement with
  friendly types (`List<TodoItem>`, `TodoItem`, `Int`, …), plus a generated
  **native adapter** that exposes JNI-callable, byte-level shims the Swift proxy
  targets.
- A `@WireletObservable` class may take `@WireletProvided`-typed parameters in
  its initializer; the generated `nativeNew(...)` accepts the Kotlin
  implementation object(s) and the Swift bridge wraps each into a proxy before
  constructing the observable instance.
- **Apple builds** compile the same Swift sources with `@WireletProvided` as an
  inert marker: the protocol is a plain Swift protocol and no JNI proxy is
  emitted. A Swift conformance can be injected directly — giving host-side
  (macOS) test parity, exactly as `@WireletObservable` degrades to a plain
  `@Observable` on Apple.

## Non-goals

- **Async / `suspend` service methods.** v1 is synchronous request/response only.
  The reactive direction (Kotlin state observed over time) is already served by
  `@WireletObservable`; a provided method returns once.
- **Callbacks / streaming from Kotlin** beyond a method's return value.
- **Kotlin exceptions surfaced as Swift `throws`.** v1 checks `ExceptionCheck`
  after each call and traps (`ExceptionDescribe` + `ExceptionClear` +
  `fatalError`). Structured error propagation is deferred.
- **Generic provided protocols**, protocol composition / inheritance on the
  provided protocol, associated types. v1 supports a single concrete protocol
  with concrete method signatures (matching the existing `@WireFormat` /
  `@WireletObservable` constraints).
- **Mixed initializer parameters.** In v1 an injected `@WireletObservable`
  initializer takes **only** `@WireletProvided` service parameters — no wire-value
  init params alongside them. (Wire-value initial state stays a stored-property
  default or a `@WireletExpose` setter.)
- **Reentrancy** — a Kotlin implementation calling back into Swift
  (`@WireletExpose`) while Swift is mid-call into Kotlin. Not supported in v1;
  documented as a constraint.
- **Non-AndroidX / desktop-JVM Kotlin.** Same target surface as the observable
  bridge.

## Annotation surface

```swift
import Wirelet           // @WireFormat etc.
import WireletProvided   // new

@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool
}

// Declared in Swift, implemented in Kotlin.
@WireletProvided
public protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}
```

Supported method parameter / return types mirror `InvokeArgClassifier`:
primitives (`Int8…Int64`, `Float`, `Double`, `Bool`), `String`, `@WireFormat`
structs/enums, and `Array` / `Optional` of those. `Void` return is allowed.

### Injecting the provided service into an observable store

```swift
import Observation
import WireletObservable
import WireletProvided

@WireletObservable
@Observable
public final class TodoListVM {
    @ObservationIgnored
    private let store: TodoStore        // a @WireletProvided protocol

    public private(set) var todos: [TodoItem] = []

    // Injected initializer — parameter typed as a @WireletProvided protocol.
    public init(store: TodoStore) {
        self.store = store
        self.todos = store.loadAll()    // hydrate from Kotlin on construction
    }

    @WireletExpose
    public func add(title: String) {
        store.add(TodoItem(id: nextID(), title: title, done: false))
        todos = store.loadAll()
    }

    @WireletExpose
    public func remove(id: Int32) {
        store.remove(id)
        todos = store.loadAll()
    }
}
```

The schema CLI first collects the set of `@WireletProvided` protocol names in the
source set, then classifies each initializer parameter as either a wire value or
a provided-service handle by matching its type against that set. No extra
per-parameter marker is required.

## Architecture

```
  Compose UI
     │  TodoListVMViewModel.create(store = RoomTodoStore())
     ▼
  TodoListVMViewModel (Kotlin, generated)
     │  nativeNew(TodoStoreNativeAdapter(store))   [external fun → JNI]
     ▼
  ┌──────────────────────────────────────────────────────────┐
  │ @_cdecl nativeNew(env, clazz, adapter: jobject) -> jlong  │   (generated)
  │   proxy = TodoStoreWireletProxy(JObject(env, adapter))    │
  │   return retain(TodoListVM(store: proxy))                 │
  └───────────────────────────┬──────────────────────────────┘
                              ▼
  TodoListVM (Swift @WireletObservable)
     │  store.loadAll() / store.add(_:) / store.remove(_:)
     ▼
  TodoStoreWireletProxy : TodoStore (Swift, generated, #if os(Android))
     │  encode args (TLV/primitive) → CallObjectMethodA / CallVoidMethodA
     │  decode return (TLV/primitive)
     ▼  JNI →
  TodoStoreNativeAdapter (Kotlin, generated)
     │  loadAllWire(): ByteArray  = WireletList.encode(impl.loadAll()){ … }
     │  addWire(bytes: ByteArray) = impl.add(TodoItemCodec.decode(bytes))
     │  removeWire(id: Int)       = impl.remove(id)
     ▼
  TodoStore (Kotlin interface, generated) — app impl over Room / DataStore
```

Observation still flows the other way unchanged: `todos` is a stored property on
the `@WireletObservable` class, exposed as `StateFlow<List<TodoItem>>` and
re-armed via the existing `Runnable` path. The provided-service calls and the
observation are independent.

### Swift side — generated proxy

`#if os(Android)`, for each `@WireletProvided` protocol, emit a final class
conforming to it, holding a generalized `JObject` (global ref to the Kotlin
adapter + `JavaVM`). Per method:

- **args** → encode each: primitives pass as `jvalue` directly; `String` via
  `NewStringUTF`; `@WireFormat` / array / optional via `WireFormatWriter` →
  `NewByteArray` + `SetByteArrayRegion`.
- **invoke** → `GetMethodID(adapterClass, "<methodWire>", "<descriptor>")` then
  `CallVoidMethodA` / `CallObjectMethodA` / `Call<Primitive>MethodA`.
- **return** → `Void` for void; primitives direct; `jbyteArray` →
  `GetByteArrayRegion` → `WireFormatReader` decode.
- `ExceptionCheck` after each call; trap on a pending exception.

On Apple builds the proxy is **not** emitted; `@WireletProvided` is inert and the
protocol is an ordinary Swift protocol.

### Generalizing `JObject`

Extend `JObject` (or add a sibling in `WireletProvided`) from the single
`call(method: "run")` shape to typed, argument-bearing calls — e.g.
`callVoid(method:signature:_ args: [jvalue])`,
`callObject(method:signature:_:) -> jobject?`,
`callInt/Long/Float/Double/Boolean(...)`. The thread-attach (`AttachCurrentThread`)
and global-ref lifetime (`DeleteGlobalRef` on `deinit`) logic is reused as-is.

### Kotlin side — generated interface + native adapter

For each `@WireletProvided` protocol, emit:

```kotlin
// Friendly interface the app implements.
interface TodoStore {
    fun loadAll(): List<TodoItem>
    fun add(item: TodoItem)
    fun remove(id: Int)
}

// Generated adapter — Swift's proxy calls these wire-level methods via JNI.
class TodoStoreNativeAdapter(private val impl: TodoStore) {
    fun loadAllWire(): ByteArray = WireletList.encode(impl.loadAll(), TodoItemCodec::encodePayload)
    fun addWire(bytes: ByteArray) { impl.add(TodoItemCodec.decode(bytes)) }
    fun removeWire(id: Int) { impl.remove(id) }
}
```

Method/return type mapping reuses `ObservableKotlinTypeMap` (Int32→Int,
`@WireFormat T`→`ByteArray`+codec, `[T]`→`List<T>`+`WireletList`, …). The wire
method names (`loadAllWire`, …) and JNI descriptors are the contract the Swift
proxy's `GetMethodID` must match exactly — both sides are generated from the same
schema, guaranteeing agreement.

### ViewModel factory wiring

The generated observable ViewModel's factory gains the injected parameter(s):

```kotlin
companion object {
    init { System.loadLibrary("ObservableCounterJNI") }
    fun create(store: TodoStore): TodoListVMViewModel =
        TodoListVMViewModel(nativeNew(TodoStoreNativeAdapter(store)))
    @JvmStatic private external fun nativeNew(store: TodoStoreNativeAdapter): Long
}
```

When the observable class has a **no-arg** initializer (the existing case), the
emitter still produces today's `nativeNew(): Long` — fully backward compatible.

## Build / codegen wiring

New, mirroring the observable modules:

- Swift: `WireletProvidedMacros` (`@WireletProvided` marker + diagnostics),
  `WireletProvidedSchema` (parse provided protocols, classify method
  params/returns and observable-init service params),
  `WireletProvidedSwiftBridgesEmitter` (emit the Swift proxy; extend the
  observable `nativeNew` bridge to wrap injected adapters),
  `WireletProvidedKotlinEmitter` (emit the Kotlin interface + native adapter),
  the `EmitWireletProvided` CLI and a `WireletProvidedBridges` build-tool plugin.
- Changed Swift: `WireletObservable` (`JObject` generalization);
  `WireletObservableSchema` + `…SwiftBridgesEmitter` + `…KotlinEmitter` (the
  injected-initializer `nativeNew(services…)` path; no-arg path unchanged).
- Kotlin: `kotlin/gradle-plugin` gains a `provided { register("main") { schemaPaths,
  interfacePackage, adapterPackage, codecPackage, … } }` DSL and a
  `GenerateWireletProvidedInterfaces` task that forks `swift run …
  emit-wirelet-provided`. Reuses `wirelet-runtime` + `wirelet-observable-runtime`
  (`WireletList` / `WireletOptional`); no new Maven artifact expected.

## Example — extend `observable-counter`

Add a Kotlin-backed `TodoStore` to the existing example rather than create a new
one (the reactive VM + Compose UI are already there):

- Declare `@WireletProvided protocol TodoStore` in the Swift target alongside
  `TodoListVM`; give `TodoListVM` the injected `init(store:)` shown above.
- Implement `TodoStore` in Kotlin over `SharedPreferences` (or an in-memory map
  seeded for the demo) — enough to prove persistence across an app restart.
- Wire `TodoListVMViewModel.create(store = …)` in the Compose entry point.
- Build the `.so`, run on emulator/device: items added in the UI survive a
  process restart because the Kotlin `TodoStore` persisted them and the Swift VM
  re-hydrates via `store.loadAll()` on construction.

## Risks & validation order

1. **Generalized `JObject` round-trip (highest value).** Before any codegen,
   hand-write a `TodoStoreWireletProxy` + `TodoStoreNativeAdapter` in the example
   and confirm a full Swift → Kotlin call with a TLV argument and a TLV return
   works on device. De-risks JNI descriptors, `jvalue` marshaling, and lifetime.
2. **Thread attach.** Provided calls run on whatever thread mutates the store
   (Compose main, or a `@WireletExpose` caller). Confirm `AttachCurrentThread`
   behaves for both the main thread and a background thread.
3. **Global-ref lifetime.** The proxy's `JObject` must `DeleteGlobalRef` when the
   Swift store is released (`nativeRelease`). Verify no leak and no
   use-after-free when `onCleared()` races an in-flight call.
4. **Injected `nativeNew` backward compatibility.** The no-arg observable path
   must keep emitting `nativeNew(): Long` unchanged.
5. **Descriptor agreement.** Swift `GetMethodID` signature strings must match the
   generated Kotlin adapter exactly — both from one schema, but assert with a
   golden test.

## Testing strategy

| Layer | Location | Coverage |
| --- | --- | --- |
| Swift proxy codec | `Sources/WireletProvided*` tests (host/macOS) | Encode args / decode returns for primitives, `String`, `@WireFormat`, arrays, optionals; round-trip against the Kotlin codec's byte layout. |
| Apple-build inertness | host test | `@WireletProvided` protocol usable with a plain Swift fake conformance; `TodoListVM(store: FakeStore())` works on macOS. |
| Kotlin adapter | `kotlin/` unit test | `TodoStoreNativeAdapter` encodes `loadAll()` and decodes `add()` bytes correctly. |
| Codegen golden | CLI tests | Generated Swift proxy + Kotlin interface/adapter match goldens; descriptors agree. |
| Android smoke | `examples/observable-counter`, manual on device | Add items, kill + relaunch, items persist (Kotlin `TodoStore`), Swift re-hydrates. |

## Phasing (for the implementation plan)

0. **De-risk** — generalize `JObject` to argument-bearing, typed-return calls;
   hand-wire proxy + adapter in `observable-counter`; prove the Swift → Kotlin
   TLV round-trip on device. No codegen yet.
1. **Schema** — `WireletProvidedSchema`: parse `@WireletProvided` protocols,
   classify method params/returns, and classify observable-init service params.
2. **Swift emitter** — `WireletProvidedSwiftBridgesEmitter`: emit the proxy;
   extend the observable `nativeNew` bridge to wrap injected adapters.
3. **Kotlin emitter + Gradle** — interface + native adapter; ViewModel factory
   injection; `provided { }` DSL + `GenerateWireletProvidedInterfaces` task.
4. **Wire the example** — Kotlin `TodoStore` (SharedPreferences) injected into
   `TodoListVM`; build `.so`; device smoke (persist across restart).
5. **Tests + docs** — unit/golden tests; README capability-table row;
   getting-started note. Replace the hand-written Phase 0 proxy/adapter with the
   generated ones.

## Open questions (resolve during planning)

- **Wire-method naming convention** — `loadAllWire` vs `loadAll__wire` vs a
  mangled scheme. Pick one collision-proof form and use it in both emitters.
- **Where the generalized JNI-call helper lives** — extend `JObject` in
  `WireletObservable`, or add a `WireletProvided` runtime type and leave
  `JObject` minimal. Leaning toward generalizing `JObject` (one global-ref
  wrapper, shared).
- **Multiple injected services** — the design allows `init(a: A, b: B)` with
  several `@WireletProvided` params; confirm the `nativeNew(a, b)` ordering and
  Kotlin factory signature in the plan.
- **`@WireletProvided` on Apple unit tests** — confirm the macro is a pure inert
  marker (no peer expansion) on non-Android so the same source compiles for
  host tests.
