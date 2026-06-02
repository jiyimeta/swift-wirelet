# Wirelet Provided bridge — Phase 4 (wire the example + device smoke) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`). Mirror named siblings; apply the stated transforms.

**Goal:** Make `@WireletProvided` work end-to-end in `examples/observable-counter`: a Swift `@WireletProvided protocol TodoStore` injected into `TodoListVM(store:)`, a Kotlin `TodoStore` impl wired through the generated interface/adapter + `create(store:)` factory, building the `.so` and passing the instrumented round-trip on the connected device.

**Architecture:** Phase 2 emitted the Swift proxy (library) and Phase 3 emitted the Kotlin interface/adapter (CLI + Gradle) + injection codegen. The one missing piece is the **Swift-side build-tool wiring**: a `EmitWireletProvidedSwiftBridges` CLI + a `WireletProvidedBridges` SwiftPM build-tool plugin, the exact analogue of the observable `EmitWireletObservableSwiftBridges` + `WireletObservableBridges`. Task 1 builds that; Tasks 2–3 wire the example and delete the hand-written stand-ins; Task 4 cross-compiles and runs the device smoke.

**Toolchain (verified present on this machine):** Swift Android SDK `swift-6.3.2-RELEASE_android`, Android SDK + `adb`, NDK (multiple), and a connected device (`adb devices` shows one). So the cross-build (`build.sh`) and `connectedDebugAndroidTest` can run here.

**Reference / golden:**
- Swift CLI + plugin to mirror: `Sources/EmitWireletObservableSwiftBridges/main.swift`, `Plugins/WireletObservableBridges/Plugin.swift`, and their `Package.swift` entries (executable target, `.executable` product, `.plugin` declaration + `capability: .buildTool()`).
- The Phase 2 emitter the CLI wraps: `Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift` (`ProvidedSwiftBridgesEmitter().emit(sources:) throws -> [(name, content)]`).
- The hand-written stand-ins to replace: `examples/observable-counter/swift/Sources/ObservableCounterJNI/{TodoStore.swift,StoreProbe.swift}` and `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt`.
- Example build scripts: `examples/observable-counter/build.sh`, `run-emulator.sh`, `verify.sh`.
- Example Gradle config: `examples/observable-counter/android-app/app/build.gradle.kts` (the `wirelet { observable { … } }` block).

**CRITICAL build-ordering gotcha (the JNI sidecar):** The Swift `WireletObservableBridges` plugin READS `Sources/ObservableCounterJNI/.wirelet-observable-jni.json` to generate `JNI_OnLoad`/`RegisterNatives`. That sidecar is WRITTEN by the Kotlin `emit-wirelet-observable` Gradle task (it writes into the Swift source dir). Changing `TodoListVM` to an injected init changes the `nativeNew` descriptor from `()J` to `(Lpkg/TodoStoreNativeAdapter;)J`. So the **committed sidecar must be regenerated (by running the Gradle observable generate task) BEFORE the `swift build` cross-compile**, otherwise the `.so`'s `JNI_OnLoad` registers `nativeNew` with the wrong descriptor → `UnsatisfiedLinkError` at `create(store=…)`. Task 4 handles this explicitly (run Gradle codegen → regen sidecar → swift build → assemble), and may need to run the generate task or `assembleDebug` once before the cross-build.

All paths under `/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`. Branch `provided-bridge`. `git -C`, absolute paths, one Bash command per call.

---

## Task 1: Swift proxy CLI + `WireletProvidedBridges` SwiftPM build-tool plugin

**Files:**
- Create `Sources/EmitWireletProvidedSwiftBridges/main.swift` — mirror `Sources/EmitWireletObservableSwiftBridges/main.swift`. Parse the SAME args that plugin passes (study the observable CLI + plugin pair to learn the exact arg contract — typically `--source <dir>`/`--output <dir>` or positional input/output). Call `ProvidedSwiftBridgesEmitter().emit(sources:)` over the `.swift` files and write each returned `(name, content)` into the output dir. NO JNI sidecar (provided proxies carry no `@_cdecl`; the injected `nativeNew` `@_cdecl` is emitted by the observable plugin). Match the observable CLI's write/idempotency behavior.
- Create `Plugins/WireletProvidedBridges/Plugin.swift` — mirror `Plugins/WireletObservableBridges/Plugin.swift`: a `BuildToolPlugin` that, for the target's `.swift` sources, runs `EmitWireletProvidedSwiftBridges` as a `prebuildCommand`/`buildCommand` (match whichever the observable plugin uses) producing `<Service>+WireletProxy.swift` into the plugin work dir, declared as build outputs so SwiftPM compiles them. Drop the observable plugin's sidecar-input logic (no sidecar here).
- Modify `Package.swift`:
  - Add `.executableTarget(name: "EmitWireletProvidedSwiftBridges", dependencies: ["WireletProvidedSwiftBridgesEmitter"])`.
  - Add product `.executable(name: "emit-wirelet-provided-swift-bridges", targets: ["EmitWireletProvidedSwiftBridges"])`.
  - Add `.plugin(name: "WireletProvidedBridges", capability: .buildTool(), dependencies: ["EmitWireletProvidedSwiftBridges"])`.
  - Add product `.plugin(name: "WireletProvidedBridges", targets: ["WireletProvidedBridges"])`.
- Test: add a plugin-contract regression test mirroring `WireletObservableBridgesPluginContract` (in `Tests/WireletProvidedSwiftBridgesEmitterTests/`): read `Plugins/WireletProvidedBridges/Plugin.swift` as text and assert its key invariant(s) (e.g. it declares the build command + output naming). Keep it light — plugin targets can't be unit-tested directly.

- [ ] Step 1: Read the observable CLI + plugin pair; note the exact arg contract + command type.
- [ ] Step 2: Write `EmitWireletProvidedSwiftBridges/main.swift`.
- [ ] Step 3: Write `Plugins/WireletProvidedBridges/Plugin.swift`.
- [ ] Step 4: `Package.swift` (executable target + executable product + plugin target + plugin product).
- [ ] Step 5: Add the plugin-contract text test.
- [ ] Step 6: `swift build --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet` (executable + plugin compile) and `swift test --package-path … --filter WireletProvidedSwiftBridgesEmitterTests` → green.
- [ ] Step 7: Commit `feat(provided): emit-wirelet-provided-swift-bridges CLI + WireletProvidedBridges SwiftPM plugin`.

---

## Task 2: Example Swift wiring — `@WireletProvided` protocol + injected `TodoListVM`

**Files (in `examples/observable-counter/swift/`):**
- Create `Sources/ObservableCounterJNI/TodoStore.swift` (REPLACE the hand-written one): just the marker-annotated protocol — DELETE the hand-written `TodoStoreProxy` (now generated by the plugin):
  ```swift
  import Wirelet
  import WireletProvided

  @WireletProvided
  public protocol TodoStore {
      func loadAll() -> [TodoItem]
      func add(_ item: TodoItem)
      func remove(_ id: Int32)
  }
  ```
- Modify `Sources/ObservableCounterJNI/TodoListVM.swift`: inject the store.
  ```swift
  @WireletObservable
  @Observable
  public final class TodoListVM {
      @ObservationIgnored private let store: TodoStore
      public var items: [TodoItem] = []
      public var filter: String = ""
      public var totalCount: Int32 = 0

      public init(store: TodoStore) {
          self.store = store
          self.items = store.loadAll()
          self.totalCount = Int32(self.items.count)
      }

      @WireletExpose public func add(_ item: TodoItem) {
          store.add(item)
          items = store.loadAll()
          totalCount = Int32(items.count)
      }
      @WireletExpose public func clear() { items.removeAll(); totalCount = 0 }
      @WireletExpose public func setDone(_ id: Int32, _ done: Bool) {
          items = items.map { $0.id == id ? TodoItem(id: $0.id, title: $0.title, done: done) : $0 }
      }
  }
  ```
  (Keep `clear`/`setDone` roughly as-is; the key change is the injected `store` + `add` writing through it + hydrating from `loadAll()`.)
- `StoreProbe.swift`: the hand-written probe references the now-deleted `TodoStoreProxy`. Update it to use the GENERATED proxy class name `TodoStoreWireletProxy` (the Phase 2 emitter names it `<Service>WireletProxy`), OR delete `StoreProbe.swift` entirely and rely on the injected-`create(store:)` path + the existing `ProvidedRoundTripInstrumentedTest` rewrite (see Task 3). DECISION: delete `StoreProbe.swift` — the real injection path supersedes the probe, and Phase 4's device test will exercise `create(store:)` end-to-end. (If keeping it is easier for an incremental device check, update it to `TodoStoreWireletProxy` instead; either is acceptable — just don't leave a dangling `TodoStoreProxy` reference.)
- Modify `Package.swift` (example): add `WireletProvidedBridges` to the target's `plugins` array and ensure the target depends on the `WireletProvided` product:
  ```swift
  .target(
      name: "ObservableCounterJNI",
      dependencies: [
          .product(name: "Wirelet", package: "swift-wirelet"),
          .product(name: "WireletObservable", package: "swift-wirelet"),
          .product(name: "WireletProvided", package: "swift-wirelet"),
      ],
      plugins: [
          .plugin(name: "WireletObservableBridges", package: "swift-wirelet"),
          .plugin(name: "WireletProvidedBridges", package: "swift-wirelet"),
      ]
  ),
  ```

- [ ] Step 1: Rewrite `TodoStore.swift` (protocol only, `@WireletProvided`).
- [ ] Step 2: Inject `TodoListVM.init(store:)` + write-through `add`.
- [ ] Step 3: Delete `StoreProbe.swift` (or repoint to `TodoStoreWireletProxy`).
- [ ] Step 4: Example `Package.swift` — add `WireletProvided` dep + `WireletProvidedBridges` plugin.
- [ ] Step 5: Host sanity: `swift build --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/examples/observable-counter/swift` (macOS host build — the proxy is `#if os(Android)`, so on host `@WireletProvided` is inert and `TodoListVM(store:)` needs a host conformance ONLY if something constructs it; the library target alone should compile. If the host build fails because nothing conforms to `TodoStore`, that's fine — confirm it's only an Android-path issue, not a syntax error. Document the result.)
- [ ] Step 6: Commit `feat(example): @WireletProvided TodoStore injected into TodoListVM (generated proxy)`.

---

## Task 3: Example Kotlin wiring — `provided { }` DSL + real impl + `create(store:)`

**Files (in `examples/observable-counter/android-app/`):**
- Modify `app/build.gradle.kts`:
  - Add a `provided { register("main") { … } }` block inside `wirelet { }`:
    ```kotlin
    provided {
        register("main") {
            schemaPaths.from(file("../../swift/Sources/ObservableCounterJNI"))
            interfacePackage.set("io.github.jiyimeta.observablecounter")
            adapterPackage.set("io.github.jiyimeta.observablecounter")
            modelPackage.set("io.github.jiyimeta.observablecounter")
            codecPackage.set("io.github.jiyimeta.observablecounter")
        }
    }
    ```
  - Add `providedAdapterPackage.set("io.github.jiyimeta.observablecounter")` to the existing `observable { register("main") { … } }` block (so the injected ViewModel imports the adapter + the sidecar gets the right descriptor).
- Replace the hand-written `app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt`: DELETE the generated-equivalent parts (the `interface TodoStore` + `TodoStoreNativeAdapter` are now generated into `build/generated/...`). Keep a REAL impl + (if the probe test is retained) the `StoreProbe`. Create a new hand-written file `TodoStoreImpl.kt` with a persistent impl so the demo proves persistence:
  ```kotlin
  package io.github.jiyimeta.observablecounter
  // A SharedPreferences-backed (or in-memory seeded) TodoStore impl.
  class InMemoryTodoStore : TodoStore {
      private val items = mutableListOf<TodoItem>()
      override fun loadAll(): List<TodoItem> = items.toList()
      override fun add(item: TodoItem) { items.add(item) }
      override fun remove(id: Int) { items.removeAll { it.id == id } }
  }
  ```
  (For the spec's "persist across restart" demo, a `SharedPreferences`-backed impl is ideal; an in-memory impl still proves the injection wiring. Pick `SharedPreferences` if straightforward, else in-memory — note which in the commit.)
- Update `MainActivity.kt` / `ViewModelFactory`: `TodoListVMViewModel.create(store = <impl>)`. The factory needs a `TodoStore` — construct the impl (e.g. `InMemoryTodoStore()` or a `SharedPreferences`-backed one needing a `Context`; if `Context` is needed, build the impl in `MainActivity.onCreate` and pass it into the factory).
- Update `ProvidedRoundTripInstrumentedTest.kt`: if `StoreProbe` was deleted in Task 2, REPLACE this test's body to exercise the real path: construct the impl, `TodoListVMViewModel.create(store = impl)`, call `vm.add(...)`, and assert the impl received the write (Swift `add` writes through `store.add`) and `vm.items` reflects `store.loadAll()`. If `StoreProbe` was kept, leave this test but ensure the adapter type it references is the generated one.
- `TodoBurstInstrumentedTest.kt`: update `TodoListVMViewModel.create()` → `create(store = InMemoryTodoStore())`.

- [ ] Step 1: `app/build.gradle.kts` — add `provided { }` + `providedAdapterPackage`.
- [ ] Step 2: Replace hand-written `TodoStore.kt` with a real impl file (interface+adapter now generated).
- [ ] Step 3: Update `MainActivity`/factory + both instrumented tests to `create(store = …)`.
- [ ] Step 4: Commit `feat(example): wire provided{} DSL + TodoStore impl + create(store=) injection`.

---

## Task 4: Cross-build + device smoke

- [ ] Step 1: **Regenerate generated Kotlin + sidecar first** (the gotcha). Run the example's Gradle generate tasks (or `assembleDebug`) once so `emit-wirelet-observable` rewrites `Sources/ObservableCounterJNI/.wirelet-observable-jni.json` with the injected `nativeNew` descriptor and `emit-wirelet-provided` generates the interface/adapter. From the example android-app dir: run the wirelet generate tasks (discover names: `generateWireletObservableViewModelsMain`, `generateWireletProvidedInterfacesMain`, `generateWireletCodecsMain`) or just `./gradlew :app:assembleDebug` (which triggers them). Inspect the regenerated sidecar to confirm `nativeNew` is `(Lio/github/jiyimeta/observablecounter/TodoStoreNativeAdapter;)J`.
- [ ] Step 2: **Cross-compile + stage + assemble**: run `examples/observable-counter/build.sh`. It publishes the runtimes/plugin to mavenLocal, cross-compiles `libObservableCounterJNI.so` (the Swift build now runs BOTH the observable and provided build-tool plugins, generating the injected bridge + the proxy), stages jniLibs, and assembles the APK. Watch for: the Swift cross-build compiling the generated `TodoStoreWireletProxy` + the injected `nativeNew` bridge. Fix any compile error in the generated/wiring (NOT by weakening — by correcting the emitter or the example wiring; if an emitter bug surfaces here it is the first real compile of generated code, so fixing it may mean a tiny Phase 2/3 emitter correction + re-running its host tests).
- [ ] Step 3: **Device smoke**: `examples/observable-counter/run-emulator.sh` (the connected device satisfies `adb wait-for-device`) → runs `:app:connectedDebugAndroidTest`. Confirm `ProvidedRoundTripInstrumentedTest` (or its replacement) AND `TodoBurstInstrumentedTest` pass — proving the injected `create(store:)` path works on device (Swift drives the Kotlin `TodoStore` through the generated proxy/adapter, and the observable StateFlow still flows).
- [ ] Step 4: If anything fails, iterate (systematic-debugging): read the actual `connectedDebugAndroidTest` failure / logcat, fix the root cause, rebuild. The most likely failure is the sidecar-ordering descriptor mismatch (Step 1) → `UnsatisfiedLinkError` on `nativeNew`; if so, ensure the sidecar regen happened before the `.so` cross-build (re-run build.sh after the sidecar is correct).
- [ ] Step 5: Commit `test(example): provided-bridge injection round-trip green on device` (include the regenerated sidecar + any committed generated artifacts that belong in the repo, matching how the observable example commits them).

---

## Self-Review

- **Spec coverage (Phase 4):** Declares `@WireletProvided protocol TodoStore` in the example, injects it into `TodoListVM(store:)`, implements `TodoStore` in Kotlin, wires `create(store=…)` in Compose, builds the `.so`, and runs the device round-trip — the spec's Phase 4 list. Replacing the hand-written Phase 0 proxy/adapter with generated ones (a Phase 5 item) happens here naturally since the example can't have both.
- **The missing-infra dependency** (Swift proxy CLI + SwiftPM plugin, Task 1) is the Swift analogue of the Phase 3 Kotlin CLI/Gradle; without it the example can't generate `TodoStoreWireletProxy`. It is host-build + plugin-contract testable.
- **The sidecar-ordering gotcha** is called out explicitly (Task 4 Step 1) because it is a runtime-only (`UnsatisfiedLinkError`) failure invisible to every host test — the injected `nativeNew` descriptor must be in the committed sidecar before the cross-build reads it.
- **Verification is real** (device): `connectedDebugAndroidTest` on the connected Pixel exercises the full injection triangle (Kotlin `create(store)` → `nativeNew(adapter)` → Swift wraps into proxy → constructs `TodoListVM` → `store.loadAll()`/`add()` cross back to Kotlin) plus the unchanged observable StateFlow path.
- **Deferred to Phase 5:** README capability-table row + getting-started note + a Kotlin-side `TodoStoreNativeAdapter` unit test + any final cleanup.
