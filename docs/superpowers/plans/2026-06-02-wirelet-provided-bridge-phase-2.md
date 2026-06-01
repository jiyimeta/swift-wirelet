# Wirelet Provided bridge — Phase 2 (Swift proxy emitter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate, from the Phase 1 `ProvidedSchema`, a Swift `<Service>WireletProxy` final class per `@WireletProvided` protocol that forwards each method across JNI to a Kotlin adapter — and add the four return-typed `JObject` call helpers the generated proxies need.

**Architecture:** Mirror `WireletObservableSwiftBridgesEmitter`. A new pure-rendering library `WireletProvidedSwiftBridgesEmitter` parses sources via `ProvidedSchemaParser` (Phase 1) and renders one `<Service>+WireletProxy.swift` file per discovered service. Per method it classifies each parameter/return with the existing public `InvokeArgClassifier` (`Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift`), then emits `JObject` calls with the matching JNI descriptor string — exactly the shape proven by the hand-written Phase 0 `TodoStoreProxy`. The proxy is `#if os(Android)` only; on Apple it is never emitted (the `@WireletProvided` protocol stays a plain protocol for host fakes). The generated code is golden-tested on macOS purely as strings; it is *compiled* later by the example cross-build (Phase 4).

**Tech Stack:** Swift 6, Foundation, `WireletProvidedSchema` (Phase 1 parser/model), `WireletObservableSchema` (the public `InvokeArgClassifier`), Swift Testing for golden tests. JNI plumbing reuses the generalized `JObject` (`Sources/WireletObservable/JObject.swift`) + raw `<jni.h>` already exposed through `CWireletJNI`.

**Scope (decided during planning):** Phase 2 is the **Swift proxy emitter only**, plus the `JObject` return helpers it depends on. The spec's other Phase 2 item — extending the observable `nativeNew` bridge to wrap injected adapters — is **moved to Phase 3**, where it pairs naturally with the Kotlin `create(store:)` factory and the observable-schema init-param parsing it requires. Neither half is device-verifiable until the Kotlin side exists (Phase 3/4), so splitting on that seam keeps Phase 2 fully host-testable.

**Type-support matrix (v1 proxy):**

| Swift type | Param (Swift → Kotlin) | Return (Kotlin → Swift) | JNI fragment |
| --- | --- | --- | --- |
| `Int8/16/32`, `UInt8/16` | `.int(Int32(x))` | `callInt` → `T(... ?? 0)` | `I` |
| `Int64`, `UInt32/64` | `.long(Int64(x))` | `callLong` → `T(... ?? 0)` | `J` |
| `Bool` | `.bool(x)` | `callBool` → `... ?? false` | `Z` |
| `Float` | `.float(x)` | `callFloat` → `... ?? 0` | `F` |
| `Double` | `.double(x)` | `callDouble` → `... ?? 0` | `D` |
| `String` | `.string(x)` | `callString` → `... ?? ""` | `Ljava/lang/String;` |
| `@WireFormat T` | `.bytes([UInt8](x.encodeToData()))` | `callBytes` → `try? T(decoding:)`, else `fatalError` | `[B` |
| `[T]` (`T` WireFormat-codable) | `.bytes(<count varint + payloads>)` | `callBytes` → varint count + `T(from:&reader)`, else `[]` | `[B` |
| `Void` (no return clause) | — | `callVoid` | `V` |
| **Optionals** (`T?`) | **deferred** — emitter throws `unsupportedType` | same | — |

Optionals are deferred deliberately: null-`jobject` argument marshaling and presence-flag decoding are extra machinery the driving use case (Folino Library / `TodoStore`) does not need. The deferral is a hard, tested boundary (the emitter throws), not a silent gap.

**Wire-method naming (locked):** `<methodName>Wire` — matches the Phase 0 contract (`addWire`/`removeWire`/`loadAllWire`) that the device round-trip already validated. The Kotlin adapter (Phase 3) must emit the same names; both sides derive them from one schema.

**Reference equivalents to mirror (read before starting):**
- Golden Phase 0 proxy (the exact target output): `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoStore.swift`
- Emitter to mirror: `Sources/WireletObservableSwiftBridgesEmitter/SwiftBridgesEmitter.swift` + `Internal/InvokeBridgeEmitter.swift`
- Classifier (reused as-is): `Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift`
- Schema (Phase 1, the input): `Sources/WireletProvidedSchema/ProvidedSchema.swift` + `ProvidedSchemaParser.swift`
- `JObject` (existing call helpers to mirror): `Sources/WireletObservable/JObject.swift`
- Array byte layout to match: `WireletObservableJNI.encodeArray` (`Sources/WireletObservable/WireletObservableJNI.swift:46`)
- Emitter test harness to mirror: `Tests/WireletObservableSwiftBridgesEmitterTests/SwiftBridgesEmitterTests.swift`

All paths below are under `/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`. Branch `provided-bridge`. Use `git -C`, absolute paths, one Bash command per call (no `&&`/`;`/`cd …`).

---

## File Structure

**Created — emitter (Task 1):**
- `Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift` — the public `emit(sources:)` entry, the error enum, and all private rendering (file, method signature, per-arg encode, per-return decode, JNI descriptor, indent). One focused file (~190 lines), single responsibility: render proxies.
- `Tests/WireletProvidedSwiftBridgesEmitterTests/ProvidedSwiftBridgesEmitterTests.swift` — Swift Testing golden tests (inline source fixtures via a `writeTmp` helper, mirroring the observable emitter tests).

**Modified — JObject (Task 2):**
- `Sources/WireletObservable/JObject.swift` — add `callLong` / `callFloat` / `callDouble` / `callString`.

**Modified (both tasks):**
- `Package.swift` — one library target, one test target (Task 1). Task 2 needs no `Package.swift` change.

---

## Task 1: `WireletProvidedSwiftBridgesEmitter` — proxy renderer + golden tests

**Files:**
- Create: `Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift`
- Create: `Tests/WireletProvidedSwiftBridgesEmitterTests/ProvidedSwiftBridgesEmitterTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Wire the new targets into `Package.swift`**

(a) Add the library target. Find this exact block (the observable Swift-bridges emitter target):

```swift
        .target(
            name: "WireletObservableSwiftBridgesEmitter",
            dependencies: [
                "WireletObservableSchema",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
```

and insert directly after it:

```swift
        .target(
            name: "WireletProvidedSwiftBridgesEmitter",
            dependencies: [
                "WireletProvidedSchema",
                "WireletObservableSchema",
            ]
        ),
```

> `WireletObservableSchema` is the home of the public `InvokeArgClassifier`. `WireletProvidedSchema` provides the parser + model. No direct swift-syntax dependency is needed — the parser does the syntax work behind `ProvidedSchemaParser.parse`.

(b) Add the test target. Find this exact block (the last test target, at the end of the array):

```swift
        .testTarget(
            name: "WireletObservableSwiftBridgesEmitterTests",
            dependencies: ["WireletObservableSwiftBridgesEmitter"]
        ),
```

and insert directly after it:

```swift
        .testTarget(
            name: "WireletProvidedSwiftBridgesEmitterTests",
            dependencies: ["WireletProvidedSwiftBridgesEmitter"]
        ),
```

> No library *product* is added in Phase 2 — the emitter is consumed by the Phase 3 CLI/plugin, exactly as `WireletObservableSwiftBridgesEmitter` was a plain target until its CLI arrived. (The observable emitter *does* have a product line today; the provided one will get its product when its CLI lands in Phase 3.)

- [ ] **Step 2: Write the failing golden tests**

Create `Tests/WireletProvidedSwiftBridgesEmitterTests/ProvidedSwiftBridgesEmitterTests.swift`:

```swift
import Foundation
import Testing
import WireletProvidedSwiftBridgesEmitter

@Suite("ProvidedSwiftBridgesEmitterTests")
struct ProvidedSwiftBridgesEmitterTests {

    private func writeTmp(name: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("provided-emitter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - The golden TodoStore (matches the Phase 0 hand-written proxy)

    @Test func todoStoreGolden() throws {
        let source = """
        import Wirelet
        import WireletProvided

        @WireletProvided
        protocol TodoStore {
            func loadAll() -> [TodoItem]
            func add(_ item: TodoItem)
            func remove(_ id: Int32)
        }
        """
        let url = try writeTmp(name: "TodoStore.swift", content: source)
        let results = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        #expect(results.count == 1)
        let (name, content) = results[0]
        #expect(name == "TodoStore+WireletProxy.swift")

        // Header + Android guard + imports
        #expect(content.contains("// Generated by emit-wirelet-provided-swift-bridges."))
        #expect(content.contains("#if os(Android)"))
        #expect(content.contains("import Wirelet"))
        #expect(content.contains("import WireletObservable"))
        #expect(content.contains("#endif"))

        // Class shape
        #expect(content.contains("final class TodoStoreWireletProxy: TodoStore {"))
        #expect(content.contains("let adapter: JObject"))
        #expect(content.contains("init(adapter: JObject) {"))

        // loadAll() -> [TodoItem] : callBytes + list decode
        #expect(content.contains("func loadAll() -> [TodoItem] {"))
        #expect(content.contains(#"adapter.callBytes(method: "loadAllWire", signature: "()[B")"#))
        #expect(content.contains("var reader = WireFormatReader(data: Data(bytes))"))
        #expect(content.contains("try? TodoItem(from: &reader)"))

        // add(_ item: TodoItem) : encode single value, void call
        #expect(content.contains("func add(_ item: TodoItem) {"))
        #expect(content.contains("let arg0Bytes = [UInt8](item.encodeToData())"))
        #expect(content.contains(#"adapter.callVoid(method: "addWire", signature: "([B)V", [.bytes(arg0Bytes)])"#))

        // remove(_ id: Int32) : primitive int arg, void call
        #expect(content.contains("func remove(_ id: Int32) {"))
        #expect(content.contains(#"adapter.callVoid(method: "removeWire", signature: "(I)V", [.int(Int32(id))])"#))
    }

    // MARK: - Primitive / bool / string / float / double returns and args

    @Test func scalarReturnsAndArgs() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol Calc {
            func ping()
            func count() -> Int32
            func total() -> Int64
            func ratio() -> Double
            func magnitude() -> Float
            func enabled() -> Bool
            func name() -> String
            func configure(_ scale: Double, _ label: String, _ flag: Bool, _ big: Int64)
        }
        """
        let url = try writeTmp(name: "Calc.swift", content: source)
        let results = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        #expect(results.count == 1)
        let content = results[0].content

        #expect(content.contains(#"adapter.callVoid(method: "pingWire", signature: "()V")"#))
        #expect(content.contains(#"return Int32(adapter.callInt(method: "countWire", signature: "()I") ?? 0)"#))
        #expect(content.contains(#"return Int64(adapter.callLong(method: "totalWire", signature: "()J") ?? 0)"#))
        #expect(content.contains(#"return adapter.callDouble(method: "ratioWire", signature: "()D") ?? 0"#))
        #expect(content.contains(#"return adapter.callFloat(method: "magnitudeWire", signature: "()F") ?? 0"#))
        #expect(content.contains(#"return adapter.callBool(method: "enabledWire", signature: "()Z") ?? false"#))
        #expect(content.contains(#"return adapter.callString(method: "nameWire", signature: "()Ljava/lang/String;") ?? """#))

        // Mixed args build the right descriptor + Arg list.
        #expect(content.contains("func configure(_ scale: Double, _ label: String, _ flag: Bool, _ big: Int64) {"))
        #expect(content.contains(#"signature: "(DLjava/lang/String;ZJ)V""#))
        #expect(content.contains("[.double(scale), .string(label), .bool(flag), .long(Int64(big))]"))
    }

    // MARK: - Array argument (encode count + payloads)

    @Test func arrayArgument() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol Bulk {
            func addAll(_ items: [TodoItem])
        }
        """
        let url = try writeTmp(name: "Bulk.swift", content: source)
        let content = try ProvidedSwiftBridgesEmitter().emit(sources: [url])[0].content
        #expect(content.contains("var writer0 = WireFormatWriter()"))
        #expect(content.contains("writer0.writeVarint(UInt64(items.count))"))
        #expect(content.contains("for element in items { element.encode(into: &writer0) }"))
        #expect(content.contains("let arg0Bytes = [UInt8](writer0.data)"))
        #expect(content.contains(#"adapter.callVoid(method: "addAllWire", signature: "([B)V", [.bytes(arg0Bytes)])"#))
    }

    // MARK: - Single @WireFormat return traps on missing/invalid bytes

    @Test func wireFormatReturn() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol Single {
            func current() -> TodoItem
        }
        """
        let url = try writeTmp(name: "Single.swift", content: source)
        let content = try ProvidedSwiftBridgesEmitter().emit(sources: [url])[0].content
        #expect(content.contains(#"adapter.callBytes(method: "currentWire", signature: "()[B")"#))
        #expect(content.contains("let value = try? TodoItem(decoding: Data(bytes))"))
        #expect(content.contains(#"fatalError("SingleWireletProxy.current: missing or invalid TodoItem from Kotlin")"#))
        #expect(content.contains("return value"))
    }

    // MARK: - Optionals are deferred — emitter throws

    @Test func optionalReturnThrows() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol Finder {
            func find(_ id: Int32) -> TodoItem?
        }
        """
        let url = try writeTmp(name: "Finder.swift", content: source)
        #expect(throws: ProvidedSwiftBridgesEmitterError.self) {
            _ = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        }
    }

    @Test func optionalParameterThrows() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol Setter {
            func setLabel(_ label: String?)
        }
        """
        let url = try writeTmp(name: "Setter.swift", content: source)
        #expect(throws: ProvidedSwiftBridgesEmitterError.self) {
            _ = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        }
    }

    // MARK: - Non-provided / non-swift inputs produce nothing

    @Test func plainProtocolProducesNoResults() throws {
        let source = """
        protocol Plain {
            func foo()
        }
        """
        let url = try writeTmp(name: "Plain.swift", content: source)
        let results = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        #expect(results.isEmpty)
    }

    @Test func nonSwiftFileIgnored() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ignore-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let results = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        #expect(results.isEmpty)
    }

    // MARK: - Multiple services in one file -> multiple files

    @Test func multipleServicesProduceMultipleFiles() throws {
        let source = """
        import WireletProvided
        @WireletProvided
        protocol A { func a() }
        @WireletProvided
        protocol B { func b() }
        """
        let url = try writeTmp(name: "Two.swift", content: source)
        let results = try ProvidedSwiftBridgesEmitter().emit(sources: [url])
        #expect(results.count == 2)
        let names = Set(results.map(\.name))
        #expect(names == ["A+WireletProxy.swift", "B+WireletProxy.swift"])
    }
}
```

- [ ] **Step 3: Run the tests to verify they FAIL to compile (the emitter type does not exist yet)**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedSwiftBridgesEmitterTests`
Expected: compile failure — `cannot find 'ProvidedSwiftBridgesEmitter' in scope` (and `ProvidedSwiftBridgesEmitterError`). This confirms the test target is wired and the symbols are genuinely missing.

- [ ] **Step 4: Implement the emitter**

Create `Sources/WireletProvidedSwiftBridgesEmitter/ProvidedSwiftBridgesEmitter.swift`:

```swift
import Foundation
import WireletObservableSchema  // InvokeArgClassifier, InvokeArgKind
import WireletProvidedSchema    // ProvidedSchema, ProvidedService, ProvidedMethod, ProvidedParameter, ProvidedSchemaParser

/// Errors surfaced while rendering a `@WireletProvided` proxy. The offline
/// CLI (Phase 3) presents these to the developer.
public enum ProvidedSwiftBridgesEmitterError: Error, Equatable {
    /// A parameter or return type is not representable by the v1 proxy.
    /// Optionals (`T?`) are deferred; every other shape classifies via
    /// `InvokeArgClassifier`.
    case unsupportedType(service: String, method: String, type: String)
}

/// Scans Swift sources for `@WireletProvided` protocols and emits, per
/// protocol, a `<Service>WireletProxy` `final class` that forwards each
/// method across JNI to the Kotlin `<Service>NativeAdapter`. Pure string
/// rendering — the back-end for the `emit-wirelet-provided-swift-bridges`
/// CLI (Phase 3). Generated files are `#if os(Android)`; on Apple the
/// `@WireletProvided` protocol stays plain and no proxy is produced.
public struct ProvidedSwiftBridgesEmitter {
    public init() {}

    /// - Returns: one `(name, content)` pair per discovered service.
    ///   `name` is `<Service>+WireletProxy.swift`.
    public func emit(sources: [URL]) throws -> [(name: String, content: String)] {
        var results: [(name: String, content: String)] = []
        for url in sources {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let schema = ProvidedSchemaParser.parse(source: source, fileName: url.lastPathComponent)
            for service in schema.services {
                let content = try renderFile(for: service)
                results.append((name: "\(service.name)+WireletProxy.swift", content: content))
            }
        }
        return results
    }

    // MARK: - File

    private func renderFile(for service: ProvidedService) throws -> String {
        let proxyName = "\(service.name)WireletProxy"
        let methods = try service.methods
            .map { try renderMethod(service: service, method: $0) }
            .joined(separator: "\n\n")
        return """
        // Generated by emit-wirelet-provided-swift-bridges.
        // Do not edit by hand.
        #if os(Android)
        import Foundation
        import Wirelet
        import WireletObservable

        final class \(proxyName): \(service.name) {
            let adapter: JObject

            init(adapter: JObject) {
                self.adapter = adapter
            }

        \(indent(methods, by: 4))
        }
        #endif
        """
    }

    // MARK: - Method

    private func renderMethod(service: ProvidedService, method: ProvidedMethod) throws -> String {
        let signature = methodSignature(method)
        let wireName = "\(method.name)Wire"

        // Encode each argument (and collect any byte-building prelude).
        var prelude: [String] = []
        var argExprs: [String] = []
        for (idx, param) in method.parameters.enumerated() {
            let use = param.internalName ?? param.label
            switch InvokeArgClassifier.classify(param.typeText) {
            case .primitive(let jni, _):
                switch jni {
                case "jlong":   argExprs.append(".long(Int64(\(use)))")
                case "jfloat":  argExprs.append(".float(\(use))")
                case "jdouble": argExprs.append(".double(\(use))")
                default:        argExprs.append(".int(Int32(\(use)))")  // jint
                }
            case .bool:
                argExprs.append(".bool(\(use))")
            case .string:
                argExprs.append(".string(\(use))")
            case .wireFormat:
                prelude.append("let arg\(idx)Bytes = [UInt8](\(use).encodeToData())")
                argExprs.append(".bytes(arg\(idx)Bytes)")
            case .array:
                prelude.append("""
                var writer\(idx) = WireFormatWriter()
                writer\(idx).writeVarint(UInt64(\(use).count))
                for element in \(use) { element.encode(into: &writer\(idx)) }
                let arg\(idx)Bytes = [UInt8](writer\(idx).data)
                """)
                argExprs.append(".bytes(arg\(idx)Bytes)")
            case .optionalPrimitive, .optionalString, .optionalWireFormat:
                throw ProvidedSwiftBridgesEmitterError.unsupportedType(
                    service: service.name, method: method.name, type: param.typeText
                )
            }
        }
        let argsTail = argExprs.isEmpty ? "" : ", [\(argExprs.joined(separator: ", "))]"
        let descriptor = try descriptor(service: service, method: method)
        let call = try renderReturn(
            service: service, method: method,
            wireName: wireName, descriptor: descriptor, argsTail: argsTail
        )

        let body = (prelude + [call]).joined(separator: "\n")
        return """
        func \(signature) {
        \(indent(body, by: 4))
        }
        """
    }

    // MARK: - Return

    private func renderReturn(
        service: ProvidedService,
        method: ProvidedMethod,
        wireName: String,
        descriptor: String,
        argsTail: String
    ) throws -> String {
        let head = "method: \"\(wireName)\", signature: \"\(descriptor)\"\(argsTail)"
        guard let returnType = method.returnTypeText else {
            return "adapter.callVoid(\(head))"
        }
        switch InvokeArgClassifier.classify(returnType) {
        case .primitive(let jni, let cast):
            switch jni {
            case "jlong":   return "return \(cast)(adapter.callLong(\(head)) ?? 0)"
            case "jfloat":  return "return adapter.callFloat(\(head)) ?? 0"
            case "jdouble": return "return adapter.callDouble(\(head)) ?? 0"
            default:        return "return \(cast)(adapter.callInt(\(head)) ?? 0)"  // jint
            }
        case .bool:
            return "return adapter.callBool(\(head)) ?? false"
        case .string:
            return "return adapter.callString(\(head)) ?? \"\""
        case .wireFormat(let typeName):
            return """
            guard let bytes = adapter.callBytes(\(head)),
                  let value = try? \(typeName)(decoding: Data(bytes)) else {
                fatalError("\(service.name)WireletProxy.\(method.name): missing or invalid \(typeName) from Kotlin")
            }
            return value
            """
        case .array(let elementTypeName):
            return """
            guard let bytes = adapter.callBytes(\(head)) else {
                return []
            }
            var reader = WireFormatReader(data: Data(bytes))
            guard let count = try? reader.readVarint() else { return [] }
            var result: [\(elementTypeName)] = []
            result.reserveCapacity(Int(count))
            for _ in 0..<Int(count) {
                guard let element = try? \(elementTypeName)(from: &reader) else { return result }
                result.append(element)
            }
            return result
            """
        case .optionalPrimitive, .optionalString, .optionalWireFormat:
            throw ProvidedSwiftBridgesEmitterError.unsupportedType(
                service: service.name, method: method.name, type: returnType
            )
        }
    }

    // MARK: - JNI descriptor

    private func descriptor(service: ProvidedService, method: ProvidedMethod) throws -> String {
        let params = method.parameters
            .map { fragment(InvokeArgClassifier.classify($0.typeText)) }
            .joined()
        let ret: String
        if let returnType = method.returnTypeText {
            ret = fragment(InvokeArgClassifier.classify(returnType))
        } else {
            ret = "V"
        }
        return "(\(params))\(ret)"
    }

    private func fragment(_ kind: InvokeArgKind) -> String {
        switch kind {
        case .primitive(let jni, _):
            switch jni {
            case "jlong":   return "J"
            case "jfloat":  return "F"
            case "jdouble": return "D"
            default:        return "I"  // jint
            }
        case .bool:
            return "Z"
        case .string, .optionalString:
            return "Ljava/lang/String;"
        case .wireFormat, .optionalPrimitive, .optionalWireFormat, .array:
            return "[B"
        }
    }

    // MARK: - Signature text

    private func methodSignature(_ method: ProvidedMethod) -> String {
        let params = method.parameters.map { param -> String in
            if let inner = param.internalName {
                return "\(param.label) \(inner): \(param.typeText)"
            }
            return "\(param.label): \(param.typeText)"
        }.joined(separator: ", ")
        if let returnType = method.returnTypeText {
            return "\(method.name)(\(params)) -> \(returnType)"
        }
        return "\(method.name)(\(params))"
    }

    // MARK: - Indent

    private func indent(_ text: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : pad + $0 }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Run the tests to verify they PASS**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedSwiftBridgesEmitterTests`
Expected: all golden tests pass. If a `.contains(...)` assertion fails, compare the emitted string against the expectation and fix the *renderer* (do not loosen the assertion unless the expectation is genuinely wrong — these strings are the contract the Kotlin adapter must match in Phase 3).

- [ ] **Step 6: Commit**

```
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet add Sources/WireletProvidedSwiftBridgesEmitter Tests/WireletProvidedSwiftBridgesEmitterTests Package.swift
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet commit -m "feat(provided): Swift proxy emitter (WireletProvidedSwiftBridgesEmitter) + golden tests"
```

---

## Task 2: `JObject` return helpers (`callLong` / `callFloat` / `callDouble` / `callString`)

The proxy emitter generates calls to four `JObject` methods that do not exist yet. The `Arg` enum already covers every *argument* shape (`int`/`long`/`bool`/`float`/`double`/`bytes`/`string`); only the *return* helpers for `jlong` / `jfloat` / `jdouble` / `jstring` are missing. They mirror the existing `callInt` / `callBool` / `callBytes` exactly and route through the same hardened `perform` (thread attach, `jclass` local-ref cleanup, exception drain).

**Files:**
- Modify: `Sources/WireletObservable/JObject.swift`

**Verification note:** `JObject.swift` is wrapped in `#if os(Android)`, so it is **excluded from the macOS host build entirely** — `swift build`/`swift test` will neither compile nor run these additions. They are compiled and exercised by the example cross-build + device round-trip in Phase 4. Phase 2 verification is by inspection: each new method must be a line-for-line analogue of an existing, device-validated helper, and the package's host test suite must still pass (proving the edit did not break the Apple build, where the file is simply absent). The four JNI functions used (`CallLongMethodA`, `CallFloatMethodA`, `CallDoubleMethodA`, `CallObjectMethodA` + `GetStringUTFChars`/`ReleaseStringUTFChars`) are all members of the `<jni.h>` `JNIEnv` struct already re-exported by `CWireletJNI` — `callBytes` already uses `CallObjectMethodA`, and the observable string bridges already use `GetStringUTFChars`/`ReleaseStringUTFChars` — so no `CWireletJNI` shim change is required.

- [ ] **Step 1: Add `callLong` / `callFloat` / `callDouble`**

In `Sources/WireletObservable/JObject.swift`, find this exact method (the existing `callBool`):

```swift
    public func callBool(method: String, signature: String, _ args: [Arg] = []) -> Bool? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            envValue.pointee.CallBooleanMethodA(env, globalRef, mid, jargs) != 0
        }
    }
```

and insert directly after it:

```swift
    public func callLong(method: String, signature: String, _ args: [Arg] = []) -> Int64? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            Int64(envValue.pointee.CallLongMethodA(env, globalRef, mid, jargs))
        }
    }

    public func callFloat(method: String, signature: String, _ args: [Arg] = []) -> Float? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            Float(envValue.pointee.CallFloatMethodA(env, globalRef, mid, jargs))
        }
    }

    public func callDouble(method: String, signature: String, _ args: [Arg] = []) -> Double? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            Double(envValue.pointee.CallDoubleMethodA(env, globalRef, mid, jargs))
        }
    }
```

- [ ] **Step 2: Add `callString`**

In the same file, find this exact method (the existing `callBytes`) and its closing — insert `callString` directly after the `callBytes` method's closing brace (just before the `// MARK: - Core` comment). The marshaling mirrors `callBytes` (flatten the `String??` from `perform`'s optional + the inner null) and reuses the observable string-decode idiom (`GetStringUTFChars` + `ReleaseStringUTFChars`):

```swift
    /// Calls a method whose JNI return type is `Ljava/lang/String;` and
    /// copies the UTF-8 contents out. Returns `nil` if the Kotlin method
    /// returned `null` or the call failed.
    public func callString(method: String, signature: String, _ args: [Arg] = []) -> String? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs -> String? in
            guard let obj = envValue.pointee.CallObjectMethodA(env, globalRef, mid, jargs) else {
                return nil
            }
            let cstr = envValue.pointee.GetStringUTFChars(env, obj, nil)
            defer {
                if let cstr { envValue.pointee.ReleaseStringUTFChars(env, obj, cstr) }
                envValue.pointee.DeleteLocalRef(env, obj)
            }
            guard let cstr else { return nil }
            return String(cString: cstr)
        // Flatten `String??` into one `nil`, mirroring callBytes.
        } ?? nil
    }
```

- [ ] **Step 3: Run the FULL host test suite to confirm no regression**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`
Expected: the whole suite passes (all existing tests + the Phase 1 schema/macro tests + the new Task 1 golden tests). Because `JObject.swift` is `#if os(Android)`, this run proves the Apple build is still clean *without* the new methods present — their Android compilation is deferred to Phase 4.

- [ ] **Step 4: Commit**

```
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet add Sources/WireletObservable/JObject.swift
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet commit -m "feat(provided): JObject return helpers (callLong/Float/Double/String) for generated proxies"
```

---

## Self-Review

- **Spec coverage (Phase 2 slice):** The spec's Phase 2 = "Swift emitter — emit the proxy; extend the observable `nativeNew` bridge to wrap injected adapters." Task 1 delivers the proxy emitter; Task 2 delivers the `JObject` return helpers the generated proxy depends on (the spec's "Generalizing `JObject`" section — Phase 0 added the arg-bearing core, Phase 2 finishes the return side). The injected-`nativeNew` half is **explicitly moved to Phase 3** (recorded in the Scope section), where it pairs with the Kotlin `create(store:)` factory + observable-schema init-param parsing it depends on; it is not silently dropped. The proxy output reproduces the Phase 0 hand-written `TodoStoreProxy` byte-for-byte in intent (same wire names, descriptors, encode/decode), so Phase 4 can replace the hand-written stand-in with the generated file.
- **Placeholder scan:** No "TBD"/"add validation"/"similar to Task N". Every code step has complete file contents or exact `Package.swift`/`JObject.swift` insertion anchors. The one inspection-only item (Task 2) is justified inline — the code is fully written; only its *Android compilation* is deferred to Phase 4, which is a property of `#if os(Android)`, not an unwritten step.
- **Type / contract consistency:**
  - Wire-method name `<name>Wire` is used identically in the emitter (`"\(method.name)Wire"`) and every test expectation (`addWire`, `removeWire`, `loadAllWire`, `pingWire`, …).
  - JNI descriptors built by `fragment(_:)` match the per-test expectations: `()V`, `()I`, `()J`, `()D`, `()F`, `()Z`, `()Ljava/lang/String;`, `()[B`, `([B)V`, `(I)V`, `(DLjava/lang/String;ZJ)V`.
  - The proxy calls exactly the `JObject` API that exists after Task 2: `callVoid`/`callInt`/`callBool`/`callBytes` (pre-existing) + `callLong`/`callFloat`/`callDouble`/`callString` (Task 2). The `Arg` cases used (`.int`/`.long`/`.bool`/`.float`/`.double`/`.string`/`.bytes`) all pre-exist in `JObject.Arg`.
  - `InvokeArgClassifier` is consumed read-only via its public surface; `jniSwiftType` strings (`"jint"`/`"jlong"`/`"jfloat"`/`"jdouble"`) are the exact values produced by `InvokeArgClassifier.primitiveJNI`, so the `switch` branches cannot silently fall through to the wrong fragment.
  - Array byte layout (`writeVarint(count)` + per-element `encode(into:)`) matches `WireletObservableJNI.encodeArray` and the Kotlin `WireletList.encode` contract recorded in the Phase 0 findings; the single-value path uses `encodeToData()` exactly as the hand-written proxy did.
  - `methodSignature` reproduces the protocol method shape from `ProvidedParameter` (`label`/`internalName`/`typeText`) — verified against `_ item: TodoItem`, `_ id: Int32`, and the multi-arg `configure` case.
- **Build ordering:** Task 1 adds its `Package.swift` target+test together with its sources, so the package always resolves; the emitter's golden tests do not depend on `JObject` (they assert strings), so Task 1 is independently testable before Task 2. Task 2 touches only the Android-guarded `JObject.swift`, so it cannot break the host build or the Task 1 tests. Either task could land first.
```
