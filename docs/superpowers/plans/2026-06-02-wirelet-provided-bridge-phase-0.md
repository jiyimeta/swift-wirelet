# Wirelet Provided bridge — Phase 0 (de-risk) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, on a real device, that a generalized `JObject` lets Swift (in the Android `.so`) call methods on a Kotlin-implemented object — passing TLV `@WireFormat` bytes and primitive arguments, and decoding a TLV byte-array return — so the `@WireletProvided` codegen in later phases can be built on a validated runtime pattern.

**Architecture:** Generalize the existing one-shot `JObject.call(method:"run")` (Swift → Kotlin `Runnable.run()`) into typed, argument-bearing JNI calls (`callVoid` / `callInt` / `callBytes` with a `JObject.Arg` enum). Then, **without any codegen**, hand-write the target shape inside the `observable-counter` example: a Swift `TodoStore` protocol + `TodoStoreProxy` (forwards across JNI via the generalized `JObject`), a Kotlin `TodoStore` interface + `TodoStoreNativeAdapter` (byte-level wire methods Swift calls) + an in-memory impl, and a hand-written `@_cdecl` JNI entry the instrumented test drives. An on-device Android instrumented test asserts the full round trip.

**Tech Stack:** Swift 6.3 (Android cross-SDK `aarch64-unknown-linux-android28`), raw JNI via `CWireletJNI`, `@WireFormat` TLV codecs (`Sources/Wirelet`), Kotlin + AndroidX instrumented test (`androidx.test`), Gradle.

**Scope note:** This plan covers **Phase 0 only** — the runtime de-risk. Phases 1–5 from the spec (`docs/superpowers/specs/2026-06-02-wirelet-provided-bridge-design.md`) — schema parsing, the Swift proxy / Kotlin interface emitters, the `nativeNew(service)` injection into `@WireletObservable`, the Gradle `provided { }` DSL, and replacing the hand-written probe with generated code — are deliberately deferred to a follow-up plan, because their exact codegen shapes depend on what this phase confirms (JNI descriptors, `jvalue` marshaling, thread-attach behavior). See **Deferred phases** at the end.

**Where the device build/run lives:** `examples/observable-counter/build.sh` (cross-compile + stage `.so` + `assembleDebug`) and `examples/observable-counter/run-emulator.sh` (install + instrumented test). Repo root referenced below as `~/Developer/Personal/swift-packages/swift-wirelet`.

---

## File Structure

**Modified (library):**
- `Sources/WireletObservable/JObject.swift` — generalize from one no-arg/void method to typed, argument-bearing calls. The existing `call(method:)` stays as a convenience wrapper so the observable re-arm path is untouched.

**Created (example — Swift, hand-written, no codegen):**
- `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoStore.swift` — the `TodoStore` protocol + `TodoStoreProxy` (the hand-written stand-in for what Phase 2 will generate).
- `examples/observable-counter/swift/Sources/ObservableCounterJNI/StoreProbe.swift` — a hand-written `@_cdecl` JNI entry the test drives (the stand-in for Phase 2's injected `nativeNew`).

**Created (example — Kotlin, hand-written, no codegen):**
- `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt` — the Kotlin `TodoStore` interface, `TodoStoreNativeAdapter` (byte-level wire methods), `InMemoryTodoStore` impl, and the `StoreProbe` object holding the `external fun`.
- `examples/observable-counter/android-app/app/src/androidTest/kotlin/io/github/jiyimeta/observablecounter/ProvidedRoundTripInstrumentedTest.kt` — the on-device assertion.

**Unchanged but relevant (read before editing):**
- `Sources/CWireletJNI/shim.h` — exposes `<jni.h>` to Swift.
- The generated `examples/observable-counter/swift/.build/.../TodoListVM+JNIBridges.swift` — the canonical pattern to mirror (`WireletObservableJNI.unwrap/retain/encodeArray/dataFromByteArray`, `@_cdecl` naming, `[TodoItem]` ↔ `jbyteArray`, `TodoItem(decoding:)`).

---

## Task 1: Generalize `JObject` to typed, argument-bearing JNI calls

**Files:**
- Modify: `Sources/WireletObservable/JObject.swift`

The current `JObject` supports exactly `call(method: "run")` → `()V`, no args. Add a `JObject.Arg` enum and `callVoid` / `callInt` / `callBool` / `callBytes` that resolve the method by name+signature, marshal arguments to a `jvalue` array (tracking and freeing local refs for object args), invoke the right `Call*MethodA`, and clear any pending Java exception. Keep `call(method:)` as a thin wrapper so the observable re-arm path is byte-for-byte unchanged.

- [ ] **Step 1: Write the new `JObject` (replace the file body)**

```swift
#if os(Android)
import CWireletJNI
import Foundation

/// Wraps a JNI `jobject` so Swift can invoke its methods without spelling
/// out the JNI ceremony. Holds a JNI **global reference** (the local ref
/// passed across an `@_cdecl` boundary would be invalid by the time a
/// later call fires) and the `JavaVM` so calls can `AttachCurrentThread`
/// from whatever thread mutates Swift state.
///
/// Originally introduced for the `@WireletObservable` re-arm path (a single
/// `Runnable.run()` call); generalized here to typed, argument-bearing
/// calls so Swift can drive a Kotlin-implemented service (`@WireletProvided`).
public final class JObject: @unchecked Sendable {
    /// A value to pass as a JNI method argument. Object-typed cases
    /// (`bytes`, `string`) allocate a local ref that the call frees.
    public enum Arg {
        case int(Int32)
        case long(Int64)
        case bool(Bool)
        case float(Float)
        case double(Double)
        case bytes([UInt8])   // -> jbyteArray ([B)
        case string(String)   // -> jstring (Ljava/lang/String;)
    }

    private let vm: UnsafeMutablePointer<JavaVM?>
    private let globalRef: jobject

    public init?(env: UnsafeMutablePointer<JNIEnv?>?, jobject local: jobject?) {
        guard let env = env, let envValue = env.pointee, let local = local else {
            return nil
        }
        var rawVM: UnsafeMutablePointer<JavaVM?>?
        let vmResult = envValue.pointee.GetJavaVM(env, &rawVM)
        guard vmResult == JNI_OK, let rawVM else { return nil }
        guard let global = envValue.pointee.NewGlobalRef(env, local) else {
            return nil
        }
        self.vm = rawVM
        self.globalRef = global
    }

    deinit {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return }
        envValue.pointee.DeleteGlobalRef(env, globalRef)
    }

    /// Convenience for the observable re-arm path: `void <name>()`.
    public func call(method name: String) {
        callVoid(method: name, signature: "()V")
    }

    public func callVoid(method: String, signature: String, _ args: [Arg] = []) {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            envValue.pointee.CallVoidMethodA(env, globalRef, mid, jargs)
            return ()
        }
    }

    public func callInt(method: String, signature: String, _ args: [Arg] = []) -> Int32? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            Int32(envValue.pointee.CallIntMethodA(env, globalRef, mid, jargs))
        }
    }

    public func callBool(method: String, signature: String, _ args: [Arg] = []) -> Bool? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            envValue.pointee.CallBooleanMethodA(env, globalRef, mid, jargs) != 0
        }
    }

    /// Calls a method whose JNI return type is `[B` (a byte array) and
    /// copies the bytes out. Returns `nil` if the Kotlin method returned
    /// `null` or the call failed.
    public func callBytes(method: String, signature: String, _ args: [Arg] = []) -> [UInt8]? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs -> [UInt8]? in
            guard let arr = envValue.pointee.CallObjectMethodA(env, globalRef, mid, jargs) else {
                return nil
            }
            let len = envValue.pointee.GetArrayLength(env, arr)
            guard len > 0 else { return [] }
            var buffer = [UInt8](repeating: 0, count: Int(len))
            buffer.withUnsafeMutableBytes { raw in
                envValue.pointee.GetByteArrayRegion(
                    env, arr, 0, len,
                    raw.baseAddress?.assumingMemoryBound(to: jbyte.self)
                )
            }
            envValue.pointee.DeleteLocalRef(env, arr)
            return buffer
        } ?? nil
    }

    // MARK: - Core

    /// Attaches the current thread, resolves the method, marshals `args`
    /// into a `jvalue` array (freeing object local refs afterwards),
    /// invokes `body`, and clears any pending Java exception.
    private func perform<R>(
        method: String,
        signature: String,
        args: [Arg],
        _ body: (UnsafeMutablePointer<JNIEnv?>, JNIEnv, jmethodID, UnsafeMutablePointer<jvalue>?) -> R
    ) -> R? {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return nil }
        guard let cls = envValue.pointee.GetObjectClass(env, globalRef) else { return nil }
        guard let mid = envValue.pointee.GetMethodID(env, cls, method, signature) else { return nil }

        var jargs: [jvalue] = []
        var localRefs: [jobject] = []
        jargs.reserveCapacity(args.count)
        for arg in args {
            switch arg {
            case .int(let v): jargs.append(jvalue(i: jint(v)))
            case .long(let v): jargs.append(jvalue(j: jlong(v)))
            case .bool(let v): jargs.append(jvalue(z: jboolean(v ? JNI_TRUE : JNI_FALSE)))
            case .float(let v): jargs.append(jvalue(f: jfloat(v)))
            case .double(let v): jargs.append(jvalue(d: jdouble(v)))
            case .bytes(let bytes):
                guard let arr = envValue.pointee.NewByteArray(env, jsize(bytes.count)) else { return nil }
                if !bytes.isEmpty {
                    bytes.withUnsafeBufferPointer { bp in
                        bp.baseAddress!.withMemoryRebound(to: jbyte.self, capacity: bytes.count) { jb in
                            envValue.pointee.SetByteArrayRegion(env, arr, 0, jsize(bytes.count), jb)
                        }
                    }
                }
                localRefs.append(arr)
                jargs.append(jvalue(l: arr))
            case .string(let s):
                guard let js = s.withCString({ envValue.pointee.NewStringUTF(env, $0) }) else { return nil }
                localRefs.append(js)
                jargs.append(jvalue(l: js))
            }
        }
        defer { for ref in localRefs { envValue.pointee.DeleteLocalRef(env, ref) } }

        let result = jargs.withUnsafeMutableBufferPointer { buf in
            body(env, envValue, mid, buf.baseAddress)
        }
        if envValue.pointee.ExceptionCheck(env) != 0 {
            envValue.pointee.ExceptionDescribe(env)
            envValue.pointee.ExceptionClear(env)
        }
        return result
    }
}
#endif
```

- [ ] **Step 2: Verify the library still compiles for the host (macOS)**

The whole file is `#if os(Android)`, so the host build just confirms nothing else broke.

Run: `swift build --package-path ~/Developer/Personal/swift-packages/swift-wirelet`
Expected: `Build complete!` (no errors). `JObject` compiles out on macOS; the observable targets are unaffected.

- [ ] **Step 3: Verify the example still cross-compiles for Android**

This compiles `JObject` for real (Android) and confirms the new code is valid against the cross-SDK, and that the untouched `call(method:)` wrapper still satisfies the generated observable bridges.

Run: `swift build --package-path ~/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/swift --swift-sdk aarch64-unknown-linux-android28 -c release`
Expected: `Build complete!` and `libObservableCounterJNI.so` produced under `.build/aarch64-unknown-linux-android28/release/`.

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Personal/swift-packages/swift-wirelet add Sources/WireletObservable/JObject.swift
git -C ~/Developer/Personal/swift-packages/swift-wirelet commit -m "feat(observable): generalize JObject to typed, argument-bearing JNI calls"
```

---

## Task 2: Kotlin side — `TodoStore` interface, native adapter, in-memory impl, probe entry

**Files:**
- Create: `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt`

This is the **hand-written stand-in** for what Phase 3 will generate. `TodoStoreNativeAdapter` exposes byte-level wire methods (`addWire`, `removeWire`, `loadAllWire`) that the Swift `TodoStoreProxy` calls via JNI; it marshals between those and the friendly `TodoStore` interface using the **already-generated** `TodoItemCodec` and the `WireletList` runtime helper (both used by the existing observable `items` path, so their byte layout already round-trips with Swift). `StoreProbe` exposes the `external fun` the test drives.

- [ ] **Step 1: Write the Kotlin file**

```kotlin
package io.github.jiyimeta.observablecounter

import io.github.jiyimeta.wirelet.observable.WireletList

/**
 * Hand-written stand-in for the Phase 3 generated `@WireletProvided`
 * artifacts. `TodoStore` is the friendly interface an app implements;
 * `TodoStoreNativeAdapter` exposes byte-level wire methods the Swift
 * proxy invokes over JNI; `InMemoryTodoStore` is a trivial impl; and
 * `StoreProbe` holds the `external fun` the instrumented test drives.
 */
interface TodoStore {
    fun loadAll(): List<TodoItem>
    fun add(item: TodoItem)
    fun remove(id: Int)
}

/** Trivial impl so the round trip has something to mutate. */
class InMemoryTodoStore : TodoStore {
    val items = mutableListOf<TodoItem>()
    override fun loadAll(): List<TodoItem> = items.toList()
    override fun add(item: TodoItem) { items.add(item) }
    override fun remove(id: Int) { items.removeAll { it.id == id } }
}

/**
 * Byte-level shim the Swift `TodoStoreProxy` targets via `GetMethodID`.
 * Method names + JNI descriptors here are the contract the Swift side
 * must match exactly:
 *   addWire     ([B)V
 *   removeWire  (I)V
 *   loadAllWire ()[B
 */
class TodoStoreNativeAdapter(private val impl: TodoStore) {
    fun addWire(bytes: ByteArray) {
        impl.add(TodoItemCodec.decode(bytes))
    }

    fun removeWire(id: Int) {
        impl.remove(id)
    }

    fun loadAllWire(): ByteArray =
        WireletList.encode(impl.loadAll()) { item, writer -> TodoItemCodec.encode(item, writer) }
}

/**
 * JNI entry the test drives. The native function is resolved by the
 * default JNI name `Java_io_github_jiyimeta_observablecounter_StoreProbe_nativeRoundTrip`
 * exported (as `@_cdecl`) from libObservableCounterJNI.so.
 */
object StoreProbe {
    init { System.loadLibrary("ObservableCounterJNI") }

    /**
     * Hands `adapter` to Swift. Swift adds two items and removes one via
     * the adapter, then returns `loadAll().count` so the test can assert
     * the full Swift -> Kotlin round trip (arg marshaling + byte return
     * decode) without re-decoding bytes in Kotlin.
     */
    external fun nativeRoundTrip(adapter: TodoStoreNativeAdapter): Int
}
```

**Note on `TodoItemCodec` / `WireletList` signatures:** these are generated/runtime types already on the classpath (the observable `items` StateFlow uses them). Before writing, confirm the exact `TodoItemCodec.encode`/`decode` and `WireletList.encode` signatures from the generated sources under `examples/observable-counter/android-app/app/build/generated/.../io/github/jiyimeta/observablecounter/` and `kotlin/observable-runtime/.../WireletList.kt`, and match the lambda shape. If `WireletList.encode`'s element-encoder parameter order differs, adjust the lambda — do not invent a new helper.

- [ ] **Step 2: Commit**

```bash
git -C ~/Developer/Personal/swift-packages/swift-wirelet add examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt
git -C ~/Developer/Personal/swift-packages/swift-wirelet commit -m "test(example): hand-written Kotlin TodoStore adapter + probe for provided-bridge de-risk"
```

---

## Task 3: Swift side — `TodoStore` protocol, `TodoStoreProxy`, and the `@_cdecl` probe

**Files:**
- Create: `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoStore.swift`
- Create: `examples/observable-counter/swift/Sources/ObservableCounterJNI/StoreProbe.swift`

`TodoStoreProxy` is the hand-written stand-in for the Phase 2 generated proxy: it conforms to a plain `TodoStore` protocol and forwards each call across JNI using the generalized `JObject`. The array decode mirrors the observable `items_set` bridge exactly (count varint + `TodoItem(from:&reader)`); the single-item encode uses `TodoItem.encodeToData()`.

- [ ] **Step 1: Write `TodoStore.swift`**

```swift
import Wirelet

#if os(Android)
import Foundation
import WireletObservable

/// Hand-written stand-in for the Phase 2 generated proxy. Mirrors the
/// future `@WireletProvided protocol TodoStore` whose implementation is
/// supplied on the Kotlin side.
protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}

/// Forwards each `TodoStore` call to a Kotlin `TodoStoreNativeAdapter`
/// over JNI. Wire-method names + descriptors must match the Kotlin
/// adapter (addWire ([B)V, removeWire (I)V, loadAllWire ()[B).
struct TodoStoreProxy: TodoStore {
    let adapter: JObject

    func loadAll() -> [TodoItem] {
        guard let bytes = adapter.callBytes(method: "loadAllWire", signature: "()[B") else {
            return []
        }
        var reader = WireFormatReader(data: Data(bytes))
        guard let count = try? reader.readVarint() else { return [] }
        var items: [TodoItem] = []
        items.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let item = try? TodoItem(from: &reader) else { return items }
            items.append(item)
        }
        return items
    }

    func add(_ item: TodoItem) {
        let bytes = [UInt8](item.encodeToData())
        adapter.callVoid(method: "addWire", signature: "([B)V", [.bytes(bytes)])
    }

    func remove(_ id: Int32) {
        adapter.callVoid(method: "removeWire", signature: "(I)V", [.int(id)])
    }
}
#endif
```

- [ ] **Step 2: Write `StoreProbe.swift`**

The `@_cdecl` symbol uses the default JNI binding name for `StoreProbe.nativeRoundTrip` (package dots → underscores), so no `RegisterNatives` / `JNI_OnLoad` change is needed. Because `StoreProbe` is a Kotlin `object`, the second JNI parameter is the `jclass`.

```swift
import Wirelet

#if os(Android)
import CWireletJNI
import Foundation
import WireletObservable

/// Test-only JNI entry. Receives the Kotlin `TodoStoreNativeAdapter`,
/// drives a Swift -> Kotlin round trip through `TodoStoreProxy`, and
/// returns the resulting `loadAll().count` so the instrumented test can
/// assert the full path (jbyteArray arg + jint arg + jbyteArray return).
@_cdecl("Java_io_github_jiyimeta_observablecounter_StoreProbe_nativeRoundTrip")
public func storeProbeNativeRoundTrip(
    _ env: UnsafeMutablePointer<JNIEnv?>?,
    _ clazz: jobject?,
    _ adapter: jobject?
) -> jint {
    guard let env, let object = JObject(env: env, jobject: adapter) else { return -1 }
    let store: TodoStore = TodoStoreProxy(adapter: object)
    store.add(TodoItem(id: 1, title: "from-swift-1", done: false))
    store.add(TodoItem(id: 2, title: "from-swift-2", done: true))
    store.remove(1)
    return jint(store.loadAll().count)
}
#endif
```

- [ ] **Step 3: Cross-compile the example for Android**

Run: `swift build --package-path ~/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/swift --swift-sdk aarch64-unknown-linux-android28 -c release`
Expected: `Build complete!`. Both new files compile into `libObservableCounterJNI.so`. (If `JObject.Arg` / `callBytes` names mismatch, fix here against Task 1.)

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Personal/swift-packages/swift-wirelet add examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoStore.swift examples/observable-counter/swift/Sources/ObservableCounterJNI/StoreProbe.swift
git -C ~/Developer/Personal/swift-packages/swift-wirelet commit -m "test(example): hand-written Swift TodoStoreProxy + @_cdecl probe for provided-bridge de-risk"
```

---

## Task 4: On-device instrumented test — the round-trip assertion

**Files:**
- Create: `examples/observable-counter/android-app/app/src/androidTest/kotlin/io/github/jiyimeta/observablecounter/ProvidedRoundTripInstrumentedTest.kt`

This is the **failing-first** test that proves Phase 0. It builds an `InMemoryTodoStore`, wraps it in the adapter, hands it to Swift via the probe, and asserts both directions: the probe's `Int` return (Swift decoded Kotlin's `loadAllWire` bytes) and the Kotlin impl's own list (Swift's `addWire`/`removeWire` arg marshaling landed).

- [ ] **Step 1: Write the instrumented test**

```kotlin
package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Drives a Swift -> Kotlin round trip through the generalized JObject:
 * Swift adds two TodoItems and removes one via the Kotlin adapter, then
 * reads the list back and returns its count. Proves jbyteArray-arg,
 * jint-arg, and jbyteArray-return marshaling across the boundary.
 */
@RunWith(AndroidJUnit4::class)
class ProvidedRoundTripInstrumentedTest {

    @Test
    fun swiftDrivesKotlinStore() {
        val impl = InMemoryTodoStore()
        val adapter = TodoStoreNativeAdapter(impl)

        val countFromSwift = StoreProbe.nativeRoundTrip(adapter)

        // Swift's loadAll() decoded Kotlin's loadAllWire() bytes: added 2, removed 1 -> 1.
        assertEquals(1, countFromSwift)

        // Swift's addWire/removeWire arg marshaling landed on the Kotlin impl.
        assertEquals(1, impl.items.size)
        assertEquals(2, impl.items[0].id)
        assertEquals("from-swift-2", impl.items[0].title)
        assertEquals(true, impl.items[0].done)
    }
}
```

- [ ] **Step 2: Build the APK (cross-compile + stage `.so` + assemble)**

Run: `~/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/build.sh`
Expected: ends with `SUCCESS. APK at: …/app-debug.apk`. (This re-runs the Android cross-build and stages the updated `.so` containing the probe.)

- [ ] **Step 3: Run the instrumented test on a device/emulator — expect PASS**

Ensure a device/emulator is connected (`adb devices` lists one). Then:

Run: `~/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/android-app/gradlew -p ~/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/android-app :app:connectedDebugAndroidTest --tests "io.github.jiyimeta.observablecounter.ProvidedRoundTripInstrumentedTest"`
Expected: `BUILD SUCCESSFUL`, the test passes.

> **TDD note:** to see it fail first, run Step 3 *before* Task 3's `.so` is staged (e.g. temporarily rename the `@_cdecl` symbol) — the probe is unresolved and the test fails with `UnsatisfiedLinkError`. Restore and rebuild to green. This is the JNI analogue of "write the failing test first": the assertion is meaningless until the Swift→Kotlin path is wired.

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Personal/swift-packages/swift-wirelet add examples/observable-counter/android-app/app/src/androidTest/kotlin/io/github/jiyimeta/observablecounter/ProvidedRoundTripInstrumentedTest.kt
git -C ~/Developer/Personal/swift-packages/swift-wirelet commit -m "test(example): on-device Swift->Kotlin provided-bridge round-trip smoke"
```

---

## Task 5: Capture findings for the codegen phases

**Files:**
- Modify: `docs/superpowers/specs/2026-06-02-wirelet-provided-bridge-design.md` (append a short "Phase 0 findings" section)

The whole point of Phase 0 is to feed the codegen design. Record what was confirmed or surprised you, so the follow-up plan starts from facts.

- [ ] **Step 1: Append a findings section to the spec**

Add, at the end of the spec, a `## Phase 0 findings (2026-06-…)` section noting at minimum:
- The exact `JObject` call API that worked (`Arg` enum, `callVoid`/`callInt`/`callBytes`, signature strings).
- Whether the default JNI name binding (`Java_<pkg>_<class>_<method>`) coexisted cleanly with the observable bridge's `RegisterNatives`/`JNI_OnLoad` (it should — different mechanism), since Phase 2's injected `nativeNew(service)` must integrate with the generated registration.
- `WireletList.encode` / `TodoItemCodec` exact signatures used (so the Kotlin emitter generates matching adapter code).
- Any thread-attach / local-ref / exception surprises.

- [ ] **Step 2: Commit**

```bash
git -C ~/Developer/Personal/swift-packages/swift-wirelet add docs/superpowers/specs/2026-06-02-wirelet-provided-bridge-design.md
git -C ~/Developer/Personal/swift-packages/swift-wirelet commit -m "docs(provided): record Phase 0 de-risk findings for codegen phases"
```

---

## Deferred phases (own plan after Phase 0)

These come from the spec's phasing and will be detailed in a follow-up plan once Phase 0 confirms the runtime shapes. They are **not** tasks in this plan:

1. **Schema** — `WireletProvidedSchema`: parse `@WireletProvided` protocols; classify method params/returns; classify `@WireletObservable`-init service params.
2. **Swift emitter** — `WireletProvidedSwiftBridgesEmitter`: generate the proxy (the hand-written `TodoStoreProxy` becomes generated); extend the observable `nativeNew` `@_cdecl` to accept injected adapter `jobject`(s) and wrap them.
3. **Kotlin emitter + Gradle** — generate the friendly interface + native adapter (replacing the hand-written `TodoStore.kt`); extend the ViewModel factory to `create(store:)`; add the `provided { }` DSL + `GenerateWireletProvidedInterfaces` task.
4. **Wire the example for real** — give `TodoListVM` an `init(store:)`, inject a Kotlin `TodoStore` (SharedPreferences) so items persist across restart; delete the hand-written probe.
5. **Tests + docs** — host codec/golden tests; README capability-table row; getting-started note.

---

## Self-Review

- **Spec coverage (Phase 0 slice):** Risk-order items 1 (generalized `JObject` round trip), 2 (thread attach — exercised by the instrumented call path), and the `Data`-style byte-array argument path are all covered by Tasks 1/3/4. Items 3–5 (global-ref lifetime under `onCleared`, injected `nativeNew` back-compat, descriptor golden) belong to the deferred codegen phases and are explicitly listed there. Phase 0's own spec phase ("generalize `JObject`; hand-wire proxy + adapter; prove the round trip on device; no codegen") maps 1:1 to Tasks 1–4, with Task 5 feeding findings forward.
- **Placeholder scan:** No "TBD"/"add error handling"/"similar to" — all code is concrete. The two "confirm exact signature" notes (Task 2 `TodoItemCodec`/`WireletList`, Task 4 TDD-fail) point at real existing generated/runtime code to read, not at unwritten work.
- **Type consistency:** Wire-method names + JNI descriptors match across sides — Kotlin `addWire([B)V` / `removeWire(I)V` / `loadAllWire()[B` (Task 2) are exactly the strings `TodoStoreProxy` passes (Task 3). `JObject.Arg` / `callVoid` / `callInt` / `callBytes` (Task 1) are used with matching names in Task 3. `StoreProbe.nativeRoundTrip` (Kotlin, Task 2) ↔ `Java_..._StoreProbe_nativeRoundTrip` (Swift `@_cdecl`, Task 3) ↔ asserted in Task 4. `TodoItem` fields (`id: Int32`, `title`, `done`) match the existing `TodoItem.swift`.
