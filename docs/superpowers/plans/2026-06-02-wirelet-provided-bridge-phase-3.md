# Wirelet Provided bridge — Phase 3 (Kotlin emitter + Gradle + injection) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Each task names a SIBLING file to mirror plus the exact NEW contract; mirror the sibling's structure/style and apply the stated transform.

**Goal:** Generate the Kotlin side of `@WireletProvided` (friendly `interface` + `<Service>NativeAdapter`) via a new emitter + CLI + Gradle task, and wire **constructor injection** so a `@WireletObservable` class with an injected initializer (`init(store: TodoStore)`) gets a Kotlin `create(store:)` factory and a Swift `nativeNew(adapter)` bridge that wraps the Kotlin adapter into the Phase 2 proxy.

**Architecture:** Mirror the `@WireletObservable` Kotlin machinery 1:1. `WireletProvidedKotlinEmitter` (+`ProvidedKotlinTypeMap`) renders one `.kt` file per service containing the friendly interface and the byte-level adapter; `EmitWireletProvided` is its CLI; the Gradle plugin gains a `provided { register("main") { … } }` DSL + `GenerateWireletProvidedInterfaces` task that forks the CLI. Injection extends the *observable* pipeline: the observable schema captures init parameters, `ConstructorEmitter` emits an injected `nativeNew(adapter…)` that wraps each adapter `jobject` into a `<Service>WireletProxy` (Phase 2) before constructing the class, the Kotlin `ViewModelEmitter` emits `create(service…)` + `nativeNew(adapter…)`, and `JNISidecarBuilder` emits the adapter-typed `nativeNew` descriptor.

**Tech Stack:** Swift 6 (SwiftSyntax parser, string-rendering emitters, Swift Testing), Kotlin (generated output; JUnit + GradleTestKit functional tests for the plugin). Reuses `kotlin/runtime` (`BinaryReader`/`BinaryWriter`) + `kotlin/observable-runtime` (`WireletList`) + generated `<Type>Codec`s.

**Scope / v1 constraints (from the design spec):**
- **Optionals are deferred** on the Kotlin side too — the type map throws `unsupportedType` for any optional param/return, mirroring the Phase 2 Swift emitter. No `WireletOptional` use in v1.
- **Injected initializers take ONLY `@WireletProvided` service parameters** (no wire-value init params alongside). A class with a no-arg init keeps today's `nativeNew(): Long` path unchanged (full backward compatibility). So when an observable class HAS init parameters, every one is treated as a provided-service handle of type `T` whose Swift proxy is `<T>WireletProxy` and whose Kotlin adapter is `<T>NativeAdapter`.
- **Multiple injected services** are supported: `init(a: A, b: B)` → `nativeNew(aAdapter, bAdapter)` in declaration order.

**Wire contract (locked, must match Phase 2 Swift proxy exactly):**
- Adapter class name: `<Service>NativeAdapter`; friendly interface name: `<Service>` (unchanged from the Swift protocol name).
- Per protocol method `m`: adapter wire method `mWire`. JNI descriptor and the param/return wire types are the EXACT duals of the Phase 2 Swift proxy (`Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift`): primitives pass as `Int`/`Long`/`Boolean`/`Float`/`Double`, `String` as `String`, `@WireFormat T` as `ByteArray` (codec), `[T]` as `ByteArray` (`WireletList`). Void return → `Unit`.

**Golden references (read before starting):**
- Hand-written Kotlin adapter Phase 2/3 must reproduce: `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoStore.kt` (interface `TodoStore` + `InMemoryTodoStore` + `TodoStoreNativeAdapter`).
- Phase 2 Swift proxy (the dual): `Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift`.
- Kotlin emitter to mirror: `Sources/WireletObservableKotlinEmitter/` (`ObservableKotlinEmitter.swift`, `ObservableCodegenConfig.swift`, `Internal/ViewModelEmitter.swift`, `Internal/ObservableKotlinTypeMap.swift`, `JNISidecarBuilder.swift`).
- CLI to mirror: `Sources/EmitWireletObservable/main.swift`.
- Gradle to mirror: `kotlin/gradle-plugin/src/main/kotlin/{WireletExtension,WireletObservableSourceSet,GenerateWireletObservableViewModels,WireletPlugin}.kt`.
- Schema/bridge to extend: `Sources/WireletObservableSchema/{ObservableSchema,ObservableSchemaParser}.swift`, `Sources/WireletObservableSwiftBridgesEmitter/{SwiftBridgesEmitter.swift,Internal/ConstructorEmitter.swift}`.
- Runtime APIs: `kotlin/observable-runtime/.../WireletList.kt` (`encode(value, encodePayload)` / `decode(bytes, decodePayload)`), generated `<T>Codec` exposes `encode`/`encodePayload`/`decode`/`decodePayload`.

All paths under `/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`. Branch `provided-bridge`. `git -C`, absolute paths, one Bash command per call.

---

## Task 1: `WireletProvidedKotlinEmitter` — friendly interface + native adapter

**Files:**
- Create `Sources/WireletProvidedKotlinEmitter/ProvidedKotlinEmitter.swift` — public entry `emit(schema: ProvidedSchema) -> [KotlinFile]`.
- Create `Sources/WireletProvidedKotlinEmitter/ProvidedCodegenConfig.swift` — config (mirror `ObservableCodegenConfig`): `interfacePackage`, `adapterPackage`, `modelPackage`, `codecPackage`, `runtimePackage` (default `io.github.jiyimeta.wirelet.observable`). Reuse the existing `KotlinFile` type — re-export or depend on `WireletObservableKotlinEmitter` for it (pick the lighter coupling: define a local `KotlinFile` only if it isn't public in the observable module; check first and reuse if public).
- Create `Sources/WireletProvidedKotlinEmitter/Internal/AdapterEmitter.swift` — renders the interface + adapter per service.
- Create `Sources/WireletProvidedKotlinEmitter/Internal/ProvidedKotlinTypeMap.swift` — the dual type map.
- Create `Tests/WireletProvidedKotlinEmitterTests/ProvidedKotlinEmitterTests.swift` — Swift Testing golden tests.
- Modify `Package.swift`: add target `WireletProvidedKotlinEmitter` (deps: `WireletProvidedSchema`, `WireletObservableSchema` for `InvokeArgClassifier`, and `WireletObservableKotlinEmitter` IF reusing `KotlinFile`) + test target.

**The type map (`ProvidedKotlinTypeMap`)** — for a Swift type text, produce:
- `friendlyType: String` — interface type: jint-primitives→`Int`, jlong-primitives→`Long`, `Bool`→`Boolean`, `Float`→`Float`, `Double`→`Double`, `String`→`String`, `@WireFormat T`→`T`, `[T]`→`List<T>`.
- `wireType: String` — adapter param/return type: primitives/bool/string same as friendly; `@WireFormat T`→`ByteArray`; `[T]`→`ByteArray`.
- `decode(_ wireExpr: String) -> String` — wire→friendly: primitives/bool/string `wireExpr`; `@WireFormat T` `"\(T)Codec.decode(\(wireExpr))"`; `[T]` `"WireletList.decode(\(wireExpr), \(T)Codec::decodePayload)"`.
- `encode(_ friendlyExpr: String) -> String` — friendly→wire: primitives/bool/string `friendlyExpr`; `@WireFormat T` `"\(T)Codec.encode(\(friendlyExpr))"`; `[T]` `"WireletList.encode(\(friendlyExpr), \(T)Codec::encodePayload)"`.
- `descriptorFragment: String` — JNI fragment (mirror Phase 2 `fragment`): jint`I`/jlong`J`/`Float`F/`Double`D/`Bool`Z/`String`Ljava/lang/String;/wireFormat+array`[B`.
- `extraImports: Set<String>` — `WireletList` import for arrays; the codec import (`<codecPackage>.<T>Codec`) for wireFormat/array; the model import (`<modelPackage>.<T>`) for wireFormat element types in the friendly interface.
- Optionals (`.optionalPrimitive`/`.optionalString`/`.optionalWireFormat`): throw `ProvidedKotlinEmitterError.unsupportedType(service:method:type:)`.

Classify via the existing public `InvokeArgClassifier.classify(_:)` (from `WireletObservableSchema`) — same enum the Phase 2 emitter used, so both sides stay in lockstep. For the Kotlin primitive name, reuse the `jniSwiftType` switch (`jint`→`Int`, `jlong`→`Long`, `jfloat`→`Float`, `jdouble`→`Double`) and `.bool`→`Boolean`.

- [ ] **Step 1: Wire `Package.swift`.** Add the target after `WireletProvidedSwiftBridgesEmitter`'s target, and the test target after `WireletProvidedSwiftBridgesEmitterTests`. First inspect whether `KotlinFile` is `public` in `Sources/WireletObservableKotlinEmitter/` — if yes, depend on `WireletObservableKotlinEmitter` and reuse it; if no, define a local `public struct KotlinFile { public var relativePath: String; public var content: String }` in this module and do NOT add that dependency.

- [ ] **Step 2: Write failing golden tests** in `Tests/WireletProvidedKotlinEmitterTests/ProvidedKotlinEmitterTests.swift`. Build a `ProvidedSchema` in-memory (e.g. via `ProvidedSchemaParser.parse` on an inline `@WireletProvided protocol TodoStore { func loadAll() -> [TodoItem]; func add(_ item: TodoItem); func remove(_ id: Int32) }`), run `ProvidedKotlinEmitter(config:).emit(schema:)`, and assert the emitted content contains (this is the contract that must match the hand-written `TodoStore.kt` + the Phase 2 Swift proxy):
  - `package <interfacePackage>` and `interface TodoStore {`
  - `fun loadAll(): List<TodoItem>`, `fun add(item: TodoItem)`, `fun remove(id: Int)` (note `_`→dropped, `Int32`→`Int`)
  - `class TodoStoreNativeAdapter(private val impl: TodoStore) {`
  - `fun loadAllWire(): ByteArray =` and `WireletList.encode(impl.loadAll(), TodoItemCodec::encodePayload)`
  - `fun addWire(bytes: ByteArray)` and `impl.add(TodoItemCodec.decode(bytes))`
  - `fun removeWire(id: Int)` and `impl.remove(id)`
  - imports: `WireletList` (from `runtimePackage`), `TodoItemCodec` (from `codecPackage`), `TodoItem` (from `modelPackage`)
  - header `// Auto-generated by emit-wirelet-provided. DO NOT EDIT.`
  - Add a `scalarsAndStringAdapter` test (a service with `func count() -> Int32`, `func label() -> String`, `func setScale(_ s: Double)`) asserting wire methods `countWire(): Int`, `labelWire(): String`, `setScaleWire(s: Double)` (primitives/string pass through, no codec).
  - Add `optionalThrows` test: a method returning `TodoItem?` → `#expect(throws: ProvidedKotlinEmitterError.self)`.
  - Decide file naming: one `.kt` file per service named `<Service>.kt` at `relativePath` `<interfacePackageAsPath>/<Service>.kt` (mirror `ViewModelEmitter`'s path logic). Assert the returned `relativePath`.

- [ ] **Step 3: Run tests → confirm compile/assert failure.** `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedKotlinEmitterTests`

- [ ] **Step 4: Implement.** Mirror `ObservableKotlinEmitter` (entry) + `ViewModelEmitter` (file scaffolding: header, package, imports, body) + `ObservableKotlinTypeMap` (the dual type map above). `AdapterEmitter.emit(service, config)` renders:
  ```kotlin
  // Auto-generated by emit-wirelet-provided. DO NOT EDIT.
  package <interfacePackage>

  <imports — sorted, deduped: model types, codec types, WireletList when any array>

  interface <Service> {
      <for each method: fun <name>(<friendly params>): <friendlyReturn or omit for Void>>
  }

  class <Service>NativeAdapter(private val impl: <Service>) {
      <for each method:
        Void:        fun <m>Wire(<wire params>) { impl.<m>(<decoded friendly args>) }
        non-Void:    fun <m>Wire(<wire params>): <wireReturn> = <encode(impl.<m>(<decoded friendly args>))>
      >
  }
  ```
  - Friendly param: `<name>: <friendlyType>` where `name = internalName ?? label`, `_` dropped. Wire param: `<name>: <wireType>`.
  - Decoded friendly arg for the impl call: `decode(<wireParamName>)`.
  - If `interfacePackage != adapterPackage`, the spec allows split packages — but for v1 emit both into ONE file in `interfacePackage` (the hand-written reference colocates them). Keep `adapterPackage` in the config for forward-compat but render the adapter in the interface file/package. (Document this in a code comment; do not over-build separate-file logic.)

- [ ] **Step 5: Run tests → green.** Same filter.

- [ ] **Step 6: Commit.** `feat(provided): Kotlin emitter (interface + native adapter) + golden tests`

---

## Task 2: `EmitWireletProvided` CLI

**Files:**
- Create `Sources/EmitWireletProvided/main.swift` — mirror `Sources/EmitWireletObservable/main.swift` exactly, swapping observable→provided: parse `--config`/`--source`/`--output`/`--include-package`; load `ProvidedCodegenConfig` from JSON; enumerate `.swift` under `--source`; parse each with `ProvidedSchemaParser.parse`; accumulate `ProvidedSchema` (sorted by service name); call `ProvidedKotlinEmitter(config:).emit(schema:)`; filter by include-packages; write idempotently; sweep stale `.kt`. NO JNI sidecar arg here (the provided adapter has no `@_cdecl` of its own — the injected `nativeNew` sidecar entry is handled by the observable pipeline in Task 4).
- Create `Tests/EmitWireletProvidedTests/EmitWireletProvidedTests.swift` — mirror `Tests/EmitWireletObservableTests/`: a CLI smoke test that writes a fixture `.swift`, a config JSON, runs the emit loop (call the CLI entry or the underlying functions), and asserts the generated `.kt` exists with the adapter contract + idempotency (second run rewrites nothing).
- Modify `Package.swift`: add `.executableTarget(name: "EmitWireletProvided", dependencies: ["WireletProvidedSchema", "WireletProvidedKotlinEmitter"])`, the `.executable(name: "emit-wirelet-provided", targets: ["EmitWireletProvided"])` product, and the test target.

- [ ] **Step 1: `Package.swift` additions** (executable target + product + test target), mirroring the observable trio.
- [ ] **Step 2: Write the CLI** mirroring `EmitWireletObservable/main.swift`. Reuse its `CLIArguments` shape minus `--jni-sidecar`. Keep the idempotent-write + stale-sweep logic identical.
- [ ] **Step 3: Write CLI test** mirroring `EmitWireletObservableTests`. Assert: generates `TodoStore.kt` with `class TodoStoreNativeAdapter`; second emit is idempotent.
- [ ] **Step 4: Run** `swift test --package-path … --filter EmitWireletProvidedTests` → green.
- [ ] **Step 5: Commit.** `feat(provided): emit-wirelet-provided CLI + tests`

---

## Task 3: Gradle `provided { }` DSL + `GenerateWireletProvidedInterfaces` task

**Files:**
- Create `kotlin/gradle-plugin/src/main/kotlin/WireletProvidedSourceSet.kt` — mirror `WireletObservableSourceSet.kt`: `schemaPaths: ConfigurableFileCollection`, `interfacePackage`, `adapterPackage`, `modelPackage`, `codecPackage`, `runtimePackage` (default `io.github.jiyimeta.wirelet.observable`), `includePackages`. No `libraryName` (no JNI lib of its own).
- Create `kotlin/gradle-plugin/src/main/kotlin/GenerateWireletProvidedInterfaces.kt` — mirror `GenerateWireletObservableViewModels.kt`: same input/output annotations, fork `swift run --package-path <swiftPackagePath> emit-wirelet-provided --config … --source … --output … [--include-package …]`. Build the config JSON with `interfacePackage`/`adapterPackage`/`modelPackage`/`codecPackage`/`runtimePackage`. No sidecar.
- Modify `kotlin/gradle-plugin/src/main/kotlin/WireletExtension.kt` — add `abstract val provided: NamedDomainObjectContainer<WireletProvidedSourceSet>` + `fun provided(configure: Action<…>)`, mirroring `observable`.
- Modify `kotlin/gradle-plugin/src/main/kotlin/WireletPlugin.kt` — add `registerProvidedSourceSet(...)` mirroring `registerObservableSourceSet`, including the JVM + Android-variant source-set wiring (output dir `build/generated/wirelet/provided/<name>/kotlin`), and call it for each `extension.provided` entry in `apply`.
- Create `kotlin/gradle-plugin/src/functionalTest/kotlin/ProvidedSourceSetTest.kt` — mirror `ObservableSourceSetTest.kt`: a GradleTestKit project that configures `provided { register("main") { … } }`, runs the generate task, and asserts the generated `<Service>.kt` adapter file appears. (If forking `swift run` inside the functional test is too slow/fragile in CI, mirror whatever stubbing the observable functional test uses — match the existing pattern exactly.)

- [ ] **Step 1: `WireletProvidedSourceSet.kt`** (DSL data holder).
- [ ] **Step 2: `GenerateWireletProvidedInterfaces.kt`** (task).
- [ ] **Step 3: Extend `WireletExtension.kt` + `WireletPlugin.kt`** (register + wire).
- [ ] **Step 4: Functional test** mirroring the observable one.
- [ ] **Step 5: Run the plugin's Gradle tests.** Use the project's documented command for the gradle-plugin module (inspect `kotlin/gradle-plugin` for the wrapper/build file; run its `test`/`functionalTest`). Confirm green.
- [ ] **Step 6: Commit.** `feat(provided): Gradle provided{} DSL + GenerateWireletProvidedInterfaces task`

---

## Task 4: Constructor injection (observable schema → Swift `nativeNew(adapter)` + Kotlin `create(service)`)

This wires a `@WireletObservable` class with an injected init to accept Kotlin adapter(s), wrapping each into the Phase 2 `<Service>WireletProxy` before constructing the Swift instance. A no-arg init keeps today's path byte-for-byte.

**Files:**
- Modify `Sources/WireletObservableSchema/ObservableSchema.swift` — add `public var initParameters: [ObservableInitParameter]` to `ObservableViewModel` (default `[]` in the initializer for source compat). Add `public struct ObservableInitParameter: Equatable, Sendable { public var label: String; public var internalName: String?; public var typeText: String }` (same shape as `ObservableMethodParameter`).
- Modify `Sources/WireletObservableSchema/ObservableSchemaParser.swift` — in the class visitor, find the designated `init` (an `InitializerDeclSyntax` member with a non-empty parameter clause) and capture its parameters into `initParameters`. If multiple inits exist, pick the one with parameters (v1 supports a single injected init); if none has parameters, leave `[]`. Ignore `init()` (no-arg).
- Modify `Sources/WireletObservableSwiftBridgesEmitter/Internal/ConstructorEmitter.swift` — `renderConstructor(className:initParameters:)`: when `initParameters` is empty, emit today's no-arg bridge unchanged. When non-empty, emit:
  ```swift
  @_cdecl("WireletObservable_<Class>_new")
  public func __<Class>_new_jni(
      _ env: UnsafeMutablePointer<JNIEnv?>?,
      _ this_or_class: jobject?,
      _ arg0: jobject?,            // one jobject? per init parameter, in order
      …
  ) -> jlong {
      guard let env else { return 0 }
      guard let obj0 = JObject(env: env, jobject: arg0) else { return 0 }   // per param
      …
      return WireletObservableJNI.retain(<Class>(<label0>: <Type0>WireletProxy(adapter: obj0), …))
  }
  ```
  where for each init param: the JNI arg is `jobject?`, it is wrapped via `JObject(env:jobject:)`, and the constructor argument is `<Type>WireletProxy(adapter: objN)` with the call-site label = `label` (omit label when `label == "_"`). `<Type>` is the param's `typeText` (the provided protocol name).
- Modify `Sources/WireletObservableSwiftBridgesEmitter/SwiftBridgesEmitter.swift` — pass `viewModel.initParameters` into `ConstructorEmitter.renderConstructor`. The generated proxy class lives in a sibling `<Service>+WireletProxy.swift` (Phase 2) compiled in the same module, so no extra import is needed beyond the existing `WireletObservable`/`Wirelet` (confirm the proxy is internal-visible — it is, same module).
- Modify `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift` — when `initParameters` is non-empty, emit the factory + native decl with adapter params instead of no-arg:
  ```kotlin
  fun create(<label>: <Service>, …): <Class>ViewModel =
      <Class>ViewModel(nativeNew(<Service>NativeAdapter(<label>), …))
  @JvmStatic
  private external fun nativeNew(<label>Adapter: <Service>NativeAdapter, …): Long
  ```
  Friendly factory param type = the service interface name `<Service>`; the `create` body wraps each in `<Service>NativeAdapter(...)`; the external `nativeNew` takes `<Service>NativeAdapter`. Param names: `internalName ?? label` (drop `_`). Add imports for each `<Service>` + `<Service>NativeAdapter` (from `interfacePackage`/`adapterPackage`). When `initParameters` is empty, keep today's `create(): … nativeNew(): Long` unchanged.
- Modify `Sources/WireletObservableKotlinEmitter/JNISidecarBuilder.swift` — the `nativeNew` method's JNI signature becomes `(Lpkg/<Service>NativeAdapter;…)J` when injected (the adapter FQN built from `adapterPackage`/`interfacePackage` + `<Service>NativeAdapter`), else `()J`. The `cdeclSymbol` stays `WireletObservable_<Class>_new`. Add whatever config field is needed (the adapter package) to compute the FQN; thread it through `ObservableCodegenConfig` if not already present.
- Tests:
  - `Tests/WireletObservableSchemaTests/…` — add a test: parsing a class with `init(store: TodoStore)` populates `initParameters == [ObservableInitParameter(label: "store", internalName: nil, typeText: "TodoStore")]`; a no-arg/`init()` class yields `[]`.
  - `Tests/WireletObservableSwiftBridgesEmitterTests/SwiftBridgesEmitterTests.swift` — add a golden test: a `@WireletObservable` class with `init(store: TodoStore)` emits the injected `nativeNew` bridge containing `_ arg0: jobject?`, `JObject(env: env, jobject: arg0)`, and `TodoStore WireletProxy`(`TodoStoreWireletProxy(adapter: obj0)`) wrapped in `WireletObservableJNI.retain(<Class>(store: TodoStoreWireletProxy(adapter: obj0)))`. Add a regression test that a no-arg class still emits the exact existing `_new` bridge (no `arg0`).
  - `Tests/WireletObservableKotlinEmitterTests/…` — add a golden test: injected class emits `fun create(store: TodoStore)` + `private external fun nativeNew(storeAdapter: TodoStoreNativeAdapter): Long` + the adapter import; a no-arg class still emits `create(): … nativeNew(): Long`.

- [ ] **Step 1: Schema model + parser** (`ObservableInitParameter`, capture init params). Write the schema test first (TDD), confirm fail, implement, green.
- [ ] **Step 2: `ConstructorEmitter` injected variant + `SwiftBridgesEmitter` threading.** Golden test first (injected + no-arg regression), confirm fail, implement, green.
- [ ] **Step 3: Kotlin `ViewModelEmitter` injected factory + sidecar signature.** Golden test first, confirm fail, implement, green.
- [ ] **Step 4: Full host suite** `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet` → all green (existing + new). Confirm no-arg observable goldens are unchanged (backward compat).
- [ ] **Step 5: Commit.** `feat(provided): constructor injection — observable nativeNew(adapter) + Kotlin create(service)`

---

## Self-Review

- **Spec coverage (Phase 3 slice):** Task 1 = Kotlin interface + native adapter (spec "interface + native adapter"); Task 2 = the CLI that drives it; Task 3 = `provided { }` DSL + `GenerateWireletProvidedInterfaces` task (spec verbatim); Task 4 = "ViewModel factory injection" + the Phase-2-deferred Swift injected `nativeNew`. Optionals are deferred consistently with Phase 2 (type map throws). The hand-written `TodoStore.kt` (interface + adapter) is reproduced by Task 1 so Phase 4 can delete the stand-in.
- **Contract consistency:** Adapter wire names `<m>Wire` and JNI descriptors are defined as the exact duals of the Phase 2 Swift proxy (same `InvokeArgClassifier`, same fragment table); the `WireletList.encode(list, TCodec::encodePayload)` / `decode(bytes, TCodec::decodePayload)` element-codec forms match the runtime API and the known-correct observable `items` path. Injected `nativeNew` arg count/order, the `<Service>WireletProxy`/`<Service>NativeAdapter` names, and the `create(service)`→`nativeNew(adapter)` wrapping all line up across the Swift bridge, the Kotlin factory, and the sidecar descriptor.
- **Backward compatibility:** Every injection change is gated on `initParameters` being non-empty; the no-arg path (today's `nativeNew(): Long`) is asserted unchanged by explicit regression tests in Task 4 Steps 2–3.
- **Decoupling check:** `WireletProvidedKotlinEmitter` reuses `InvokeArgClassifier` (public, from `WireletObservableSchema`) rather than re-implementing classification; `KotlinFile` is reused if public (checked in Task 1 Step 1) to avoid a divergent type.
- **Deferred to Phase 4/5:** wiring the real example (`TodoStore` Kotlin impl + `TodoListVM(store:)` + Compose `create(store=…)`), the Android cross-build, and the device round-trip are Phase 4; deleting the hand-written stand-ins + docs are Phase 5.
