# Wirelet Provided bridge — Phase 5 (tests + docs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Close out the `@WireletProvided` capability with the remaining host test (Apple-build inertness / host parity) and user-facing docs (README capability section + repo-layout row + getting-started DSL), so the feature is documented and the spec's testing strategy is fully covered.

**Architecture:** Phases 1–4 delivered the schema, macro, Swift proxy emitter + JObject helpers, Kotlin interface/adapter emitter + CLI + Gradle, constructor injection, and a device-validated example. Phase 5 adds the one remaining test from the spec's testing-strategy table (host inertness) and the documentation, mirroring how the observable bridge is documented.

**Context — what is already covered (do NOT rebuild):**
- Swift proxy codec golden tests: `Tests/WireletProvidedSwiftBridgesEmitterTests`.
- Kotlin interface/adapter golden tests: `Tests/WireletProvidedKotlinEmitterTests`.
- CLI: `Tests/EmitWireletProvidedTests`. Gradle: `ProvidedSourceSetTest` (functionalTest).
- Schema + macro: `Tests/WireletProvidedSchemaTests`, `Tests/WireletProvidedMacrosTests`.
- Constructor injection goldens (Swift bridge + Kotlin factory + sidecar): added in Phase 3.
- **Android smoke (device):** Phase 4 — `ProvidedRoundTripInstrumentedTest` + `TodoBurstInstrumentedTest` pass on the Pixel 8a.
- The hand-written Phase 0 proxy/adapter stand-ins were already **deleted** and replaced by generated code in Phase 4.

The spec testing-strategy row still missing is **"Apple-build inertness — `@WireletProvided` protocol usable with a plain Swift fake conformance on macOS."** (The "Kotlin adapter unit test" row is already satisfied by the Phase 3 adapter golden test + the device round-trip exercising the real generated adapter; a separate hand-written Kotlin unit test would duplicate that — skip it, noted here so it isn't silently dropped.)

All paths under `/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`. Branch `provided-bridge`. `git -C`, absolute paths, one Bash command per call.

---

## Task 1: Apple-build inertness host test

Proves the spec claim: on Apple platforms a `@WireletProvided` protocol is an ordinary Swift protocol (the marker macro emits nothing), so a plain Swift conformance can be injected directly for host unit tests — giving macOS test parity.

**Files:**
- Create `Tests/WireletProvidedTests/InertnessTests.swift` — Swift Testing.
- Modify `Package.swift`: add `.testTarget(name: "WireletProvidedTests", dependencies: ["WireletProvided", "Wirelet"])` after the `WireletProvidedMacrosTests` test target.

- [ ] **Step 1: `Package.swift`** — add the test target.

- [ ] **Step 2: Write the test** `Tests/WireletProvidedTests/InertnessTests.swift`:

```swift
import Testing
import Wirelet
import WireletProvided

// A @WireFormat value used by the provided protocol below.
@WireFormat
struct Note: Equatable, Sendable {
    var id: Int32
    var text: String
}

// On Apple platforms @WireletProvided is an inert marker: this is a plain
// Swift protocol, so a host fake can conform directly.
@WireletProvided
protocol NoteStore {
    func loadAll() -> [Note]
    func add(_ note: Note)
    func remove(_ id: Int32)
}

// A plain Swift fake conformance — only possible because the marker emits
// no proxy/requirements on the host.
final class FakeNoteStore: NoteStore {
    private(set) var notes: [Note] = []
    func loadAll() -> [Note] { notes }
    func add(_ note: Note) { notes.append(note) }
    func remove(_ id: Int32) { notes.removeAll { $0.id == id } }
}

// A consumer that takes the provided protocol by injection — mirrors how a
// @WireletObservable class would on the host (where @WireletProvided is inert).
final class NoteListModel {
    private let store: NoteStore
    private(set) var notes: [Note]
    init(store: NoteStore) {
        self.store = store
        self.notes = store.loadAll()
    }
    func add(_ note: Note) {
        store.add(note)
        notes = store.loadAll()
    }
}

@Suite("WireletProvided Apple-build inertness")
struct InertnessTests {
    @Test func fakeConformanceUsableOnHost() {
        let fake = FakeNoteStore()
        let model = NoteListModel(store: fake)
        #expect(model.notes.isEmpty)

        model.add(Note(id: 1, text: "first"))
        model.add(Note(id: 2, text: "second"))
        #expect(model.notes.count == 2)
        #expect(fake.notes.map(\.id) == [1, 2])
        #expect(model.notes.last?.text == "second")
    }

    @Test func injectedModelHydratesFromStore() {
        let fake = FakeNoteStore()
        fake.add(Note(id: 7, text: "seed"))
        // Construction hydrates via store.loadAll() — proving the injected
        // protocol is a live, ordinary Swift dependency on the host.
        let model = NoteListModel(store: fake)
        #expect(model.notes == [Note(id: 7, text: "seed")])
    }
}
```

- [ ] **Step 3: Run** `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedTests` → green. (If it fails to compile because the `@WireletProvided` macro is NOT inert on host — e.g. it injects requirements — that is a real defect to investigate; the macro is supposed to be diagnostic-only/peer-empty.)

- [ ] **Step 4: Full suite** `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet` → all green.

- [ ] **Step 5: Commit** `test(provided): Apple-build inertness — @WireletProvided protocol usable with a host fake`.

---

## Task 2: Documentation

**Files:**
- Modify `README.md`: add a `## Provided bridge` section + a repo-layout row + extend the status line.
- Modify `docs/getting-started-kotlin.md`: add a `provided { … }` DSL section.

- [ ] **Step 1: README `## Provided bridge` section.** Insert a new section immediately AFTER the `## Observable bridge` section (which ends at the line referencing `examples/observable-counter/`) and BEFORE `## Repository layout`. Mirror the observable section's structure (intro paragraph, Swift snippet, Kotlin snippet, "What gets generated", wire-it-in pointer). Content to convey:
  - `@WireletProvided` is the mirror of `@WireletObservable`: it lets Swift code (in an Android `.so`) call into a **Kotlin-implemented** protocol over JNI. Declare a Swift `protocol` with `@WireletProvided`; implement it on the Kotlin side; Swift invokes it with value-typed args/returns marshaled through the `@WireFormat` TLV codecs.
  - A `@WireletObservable` class can take `@WireletProvided`-typed init parameters; the generated `create(service:)` factory accepts the Kotlin impl and the Swift bridge wraps it into a generated proxy before constructing the observable instance.
  - On Apple builds `@WireletProvided` is inert (a plain protocol) — inject a Swift fake for host tests.
  - Swift snippet:
    ```swift
    import Wirelet
    import WireletProvided

    @WireletProvided
    public protocol TodoStore {
        func loadAll() -> [TodoItem]
        func add(_ item: TodoItem)
        func remove(_ id: Int32)
    }

    @WireletObservable @Observable
    public final class TodoListVM {
        @ObservationIgnored private let store: TodoStore
        public var items: [TodoItem] = []
        public init(store: TodoStore) {           // injected Kotlin service
            self.store = store
            self.items = store.loadAll()
        }
        @WireletExpose public func add(_ item: TodoItem) {
            store.add(item); items = store.loadAll()
        }
    }
    ```
  - Kotlin snippet:
    ```kotlin
    // Generated: interface + native adapter.
    interface TodoStore { fun loadAll(): List<TodoItem>; fun add(item: TodoItem); fun remove(id: Int) }
    class TodoStoreNativeAdapter(impl: TodoStore) { /* byte-level wire methods the Swift proxy calls */ }

    // App implements the friendly interface and injects it:
    class RoomTodoStore : TodoStore { /* … */ }
    val vm = TodoListVMViewModel.create(store = RoomTodoStore())
    ```
  - "What gets generated":
    - **Swift side** (SwiftPM `WireletProvidedBridges` build-tool plugin via `emit-wirelet-provided-swift-bridges`): a `<Service>WireletProxy` `final class` per `@WireletProvided` protocol that forwards each method across JNI; plus, for an injected `@WireletObservable` initializer, the `nativeNew(adapter…)` bridge wraps each Kotlin adapter into its proxy.
    - **Kotlin side** (Gradle task via `emit-wirelet-provided`): a friendly `interface <Service>` + a `<Service>NativeAdapter` exposing byte-level wire methods; the injected ViewModel gains `create(service…)` + an adapter-typed `nativeNew`.
  - Wire-it-in pointer: apply the `io.github.jiyimeta.wirelet` Gradle plugin and add a `provided { … }` block (+ `providedAdapterPackage` on the `observable { }` block when injecting) — see `docs/getting-started-kotlin.md` and `examples/observable-counter/`.
  - Note the v1 constraints briefly: synchronous methods only; injected initializers take only `@WireletProvided` service params; optionals deferred.

- [ ] **Step 2: README repo-layout row.** In the `## Repository layout` table, add directly after the `Sources/WireletObservable* + Plugins/WireletObservableBridges/` row:
  ```
  | `Sources/WireletProvided*` + `Plugins/WireletProvidedBridges/` | `@WireletProvided` Swift protocol → Kotlin-implemented service callable from Swift over JNI — Swift proxy produced by a SwiftPM build tool plugin, Kotlin interface/adapter by `emit-wirelet-provided`. |
  ```
  Also extend the `examples/observable-counter/` row to mention it now also demos the provided bridge (Swift `TodoListVM` injected with a Kotlin `TodoStore`), or add a short clause.

- [ ] **Step 3: README status line.** Update the "Status" paragraph to note the Provided bridge (`@WireletProvided` — Swift → Kotlin service calls) is now implemented on branch `provided-bridge` (device-validated). Keep it factual; do not claim a published tag/version it doesn't have.

- [ ] **Step 4: `docs/getting-started-kotlin.md` `provided { }` section.** Read the file's existing `observable { }` DSL section and mirror it: document the `provided { register("main") { schemaPaths / interfacePackage / adapterPackage / modelPackage / codecPackage / runtimePackage } }` block, and the `providedAdapterPackage` property on the `observable { }` block needed when injecting a service into a `@WireletObservable` class. Show the `create(store = …)` use site. Match the doc's existing tone/structure.

- [ ] **Step 5: Commit** `docs(provided): README Provided bridge section + layout row + getting-started DSL`.

---

## Self-Review

- **Spec coverage (Phase 5):** Adds the missing host-inertness test (the one open row in the spec testing-strategy table) and the docs (README capability section + layout row, getting-started DSL). The "replace hand-written stand-ins with generated" item was completed in Phase 4. The "Kotlin adapter unit test" row is satisfied by the Phase 3 adapter golden + the Phase 4 device round-trip (a separate hand-written Kotlin unit test would duplicate generated-code behavior already validated end-to-end) — explicitly noted, not silently dropped.
- **No placeholders:** Task 1 has the complete test file. Task 2 specifies exact insertion points (after `## Observable bridge`, the layout-row text verbatim) and the content to convey with ready snippets; the prose is written against the existing README structure.
- **Consistency:** The README Provided section mirrors the Observable section's shape; the layout row mirrors the observable row's wording; the getting-started section mirrors the existing observable DSL section. Snippets use the same `TodoStore`/`TodoListVM` names as the example and the rest of the docs.
- **Verification:** Task 1 is host-test-gated (`swift test`); Task 2 is docs (no test), reviewed for accuracy against the shipped behavior (generated names, DSL properties, plugin/CLI names all match what Phases 2–4 actually produce).
