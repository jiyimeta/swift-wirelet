# Wirelet Observable — Multi-arg `@WireletExpose` Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the Phase 1 restriction that `@WireletExpose` only allows zero-arg methods or a single `@WireFormat` argument. After this plan, `@WireletExpose` accepts any number of arguments mixing primitive, `String`, `@WireFormat`, `Optional`, and `Array` types — bridged natively (no allocation overhead for primitives, no hidden wrapper struct).

**Architecture:** Native per-arg JNI cross. Each `@WireletExpose` method emits one `@_cdecl` global function whose signature contains one parameter per Swift arg, typed via the same per-arg conversion logic that the property setters already use (`jint` for `Int32`, `jboolean` for `Bool`, `jstring?` for `String`, `jbyteArray?` for `@WireFormat`/`Optional`/`Array`). The Kotlin emitter generates a matching `external fun` whose JNI signature concatenates per-arg descriptors. No wrapper structs are synthesised; debugger stack traces show the user method directly; no Kotlin `ByteArray` allocation per call when args are primitive-only.

**Tech Stack:** Swift 6.3.2 + SwiftSyntax 603 (host macro / schema), Swift Android SDK `aarch64-unknown-linux-android28` (cross-build), Kotlin 2.0.21 (Android consumer + emitter output), Gradle 8.10 + AGP 8.7 (consumer build), `androidx.test.ext:junit` instrumented harness on Pixel 8a or emulator API 28+.

---

## File Structure

**Modify:**
- `Sources/WireletObservableMacros/WireletObservableMacro.swift:33-50` — relax the `@WireletExpose` arity / type diagnostic so anything classifiable is accepted; only truly unrepresentable types diagnose.
- `Sources/WireletObservableMacros/WireletObservableDiagnostic.swift:7,21-22` — rewrite the `unsupportedExposedMethodSignature` message to describe the remaining ban (currently it claims "Phase 1 limit").
- `Sources/WireletObservableSchema/ObservableSchema.swift:92-103` — drop the doc-comment claim that v0.1 only supports zero- or one-arg.
- `Sources/WireletObservableSchema/ObservableSchemaParser.swift:77-95` — no logic change but the comment block referring to "Phase 1" goes away.
- `Sources/WireletObservableSwiftBridgesEmitter/Internal/InvokeBridgeEmitter.swift` — replace `renderOneArg`-only path with an N-arg renderer that dispatches per arg type. Reuse the conversion patterns from `SetterBridgeEmitter`.
- `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift:160-205` — emit multi-arg `external fun nativeXxx(self: Long, arg0: T0, arg1: T1, ...)` and a matching public wrapper function.
- `Sources/WireletObservableKotlinEmitter/JNISidecarBuilder.swift:151-178` — build N-arg JNI signature by concatenating per-arg descriptors (e.g. `(JIZ)V`).
- `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift` — add `setDone(_ id: Int32, _ done: Bool)` `@WireletExpose` method.
- `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoScreen.kt` — wire `Checkbox(onCheckedChange:)` through `viewModel.setDone(item.id, it)`.
- `docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md` — retrospective addendum.

**Create:**
- `Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift` — pure mapping from `ObservableMethodParameter.typeText` → an enum describing the JNI parameter type, the Swift-side conversion expression, and the JNI signature descriptor. Single source of truth so the three emitters (Swift bridges, Kotlin emitter, JNI sidecar) never drift.
- `Tests/WireletObservableSchemaTests/InvokeArgClassifierTests.swift` — covers every category (primitive, Bool, String, `@WireFormat`, Optional flavors, Array).
- `Tests/WireletObservableSwiftBridgesEmitterTests/Fixtures/MultiArgVM.expected.swift` — golden file for a 3-arg method covering `Int32 + Bool + TodoItem`.
- `Tests/WireletObservableKotlinEmitterTests/Fixtures/MultiArgVMViewModel.expected.kt` — golden file for the matching Kotlin emission.

**Out of scope:**
- `Throws` methods. The macro continues to reject `@WireletExpose func foo() throws`.
- Return values. Methods still must return `Void`. (Adds JNI return-type marshaling; orthogonal.)
- Default arguments + labeled args beyond what the current single-arg path supports (the existing `param.label`/`param.internalName` plumbing is reused as-is).
- Diff-based `Array<T>` setter updates (separate spec deferred item).

---

## Task 1: Add `InvokeArgClassifier`

**Files:**
- Create: `Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift`
- Create: `Tests/WireletObservableSchemaTests/InvokeArgClassifierTests.swift`
- Modify: `Package.swift` — only if `WireletObservableSchemaTests` doesn't already exist; check first.

- [ ] **Step 1: Confirm the test target exists**

Run: `swift package describe --type json | grep -A 2 'WireletObservableSchemaTests'`
Expected: shows the target. If absent, add it to `Package.swift` (mirror `WireletObservableKotlinEmitterTests`).

- [ ] **Step 2: Write the failing test**

```swift
// Tests/WireletObservableSchemaTests/InvokeArgClassifierTests.swift
import Testing
@testable import WireletObservableSchema

@Suite struct InvokeArgClassifierTests {
    @Test func primitiveInt32() {
        let kind = InvokeArgClassifier.classify("Int32")
        #expect(kind == .primitive(jniSwiftType: "jint", swiftCast: "Int32"))
    }

    @Test func primitiveBool() {
        let kind = InvokeArgClassifier.classify("Bool")
        #expect(kind == .bool)
    }

    @Test func primitiveInt64() {
        let kind = InvokeArgClassifier.classify("Int64")
        #expect(kind == .primitive(jniSwiftType: "jlong", swiftCast: "Int64"))
    }

    @Test func primitiveFloat() {
        let kind = InvokeArgClassifier.classify("Float")
        #expect(kind == .primitive(jniSwiftType: "jfloat", swiftCast: "Float"))
    }

    @Test func string() {
        let kind = InvokeArgClassifier.classify("String")
        #expect(kind == .string)
    }

    @Test func wireFormatStruct() {
        let kind = InvokeArgClassifier.classify("TodoItem")
        #expect(kind == .wireFormat(typeName: "TodoItem"))
    }

    @Test func optionalPrimitive() {
        let kind = InvokeArgClassifier.classify("Int32?")
        #expect(kind == .optionalPrimitive(innerTypeName: "Int32"))
    }

    @Test func optionalString() {
        let kind = InvokeArgClassifier.classify("String?")
        #expect(kind == .optionalString)
    }

    @Test func optionalWireFormat() {
        let kind = InvokeArgClassifier.classify("TodoItem?")
        #expect(kind == .optionalWireFormat(typeName: "TodoItem"))
    }

    @Test func arrayOfWireFormat() {
        let kind = InvokeArgClassifier.classify("[TodoItem]")
        #expect(kind == .array(elementTypeName: "TodoItem"))
    }
}
```

- [ ] **Step 3: Run test, confirm failure**

Run: `swift test --filter InvokeArgClassifierTests`
Expected: FAIL — `cannot find 'InvokeArgClassifier' in scope`.

- [ ] **Step 4: Implement the classifier**

```swift
// Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift

/// Classification of a single `@WireletExpose` method parameter type.
///
/// The Swift bridges emitter, Kotlin emitter, and JNI sidecar builder all
/// consult this enum so their decisions stay in lockstep. Adding a new
/// category here is the single editable point.
public enum InvokeArgKind: Equatable, Sendable {
    /// `Int8/16/32/64`, `UInt8/16/32/64`, `Float`, `Double`.
    /// `jniSwiftType` is the Swift name of the JNI primitive
    /// (e.g. `jint`); `swiftCast` is the Swift type the bridge converts to
    /// before calling the user method (e.g. `Int32`).
    case primitive(jniSwiftType: String, swiftCast: String)
    /// `Bool` — its own case because conversion is `(arg != 0)`, not
    /// `Bool(arg)`.
    case bool
    /// `String`.
    case string
    /// A non-optional `@WireFormat` struct/enum.
    case wireFormat(typeName: String)
    /// `Int32?` etc.
    case optionalPrimitive(innerTypeName: String)
    /// `String?`.
    case optionalString
    /// `T?` where `T` is `@WireFormat`.
    case optionalWireFormat(typeName: String)
    /// `[T]` where `T` is `@WireFormat`.
    case array(elementTypeName: String)
}

public enum InvokeArgClassifier {
    public static func classify(_ typeText: String) -> InvokeArgKind {
        // Order matters: more specific patterns first.
        if typeText.hasSuffix("?") {
            let inner = String(typeText.dropLast())
            return classifyOptional(innerTypeName: inner)
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            let inner = String(typeText.dropFirst("Optional<".count).dropLast())
            return classifyOptional(innerTypeName: inner)
        }
        if typeText.hasPrefix("["), typeText.hasSuffix("]") {
            let element = String(typeText.dropFirst().dropLast())
            return .array(elementTypeName: element)
        }
        if let primitive = primitiveJNI(typeText) {
            if typeText == "Bool" { return .bool }
            return .primitive(jniSwiftType: primitive, swiftCast: typeText)
        }
        if typeText == "String" { return .string }
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(innerTypeName: String) -> InvokeArgKind {
        if primitiveJNI(innerTypeName) != nil {
            return .optionalPrimitive(innerTypeName: innerTypeName)
        }
        if innerTypeName == "String" { return .optionalString }
        return .optionalWireFormat(typeName: innerTypeName)
    }

    private static func primitiveJNI(_ typeText: String) -> String? {
        switch typeText {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "jint"
        case "Int64", "UInt32", "UInt64":                 return "jlong"
        case "Bool":   return "jboolean"
        case "Float":  return "jfloat"
        case "Double": return "jdouble"
        default: return nil
        }
    }
}
```

- [ ] **Step 5: Run test, confirm pass**

Run: `swift test --filter InvokeArgClassifierTests`
Expected: PASS, 10 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift \
        Tests/WireletObservableSchemaTests/InvokeArgClassifierTests.swift
git commit -m "feat(observable): add InvokeArgClassifier for multi-arg method support"
```

---

## Task 2: Lift macro diagnostic; teach it to use the classifier

**Files:**
- Modify: `Sources/WireletObservableMacros/WireletObservableMacro.swift:33-50`
- Modify: `Sources/WireletObservableMacros/WireletObservableDiagnostic.swift:7,21-22`
- Modify: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift` — relax the existing snapshot test that expected the 2-arg method to diagnose.

The current macro rejects any method with `>1` parameter, and any 1-arg method whose arg is primitive or `String`. After this change it should:

- Accept any method whose parameters are all classifiable (uses `InvokeArgClassifier`).
- Continue to diagnose Tuple, KeyPath, etc. — these don't classify cleanly.

Because the classifier's fallback is `.wireFormat(typeName:)` (it treats anything unrecognised as a `@WireFormat` type), the macro can't actually detect "unrepresentable" syntactically. **That's acceptable:** if the user writes `@WireletExpose func foo(_ x: (Int, Int))`, the schema-level fallback will produce a `wireFormat(typeName: "(Int, Int)")` entry and the Swift bridges emitter will fail to compile the generated code (since `(Int, Int)` isn't `WireFormat`-conformant). That's a compile-time error at the bridge layer, which is still actionable for the consumer.

The macro-side diagnostic becomes vestigial. Repurpose it:

- [ ] **Step 1: Update the diagnostic enum text**

Replace `Sources/WireletObservableMacros/WireletObservableDiagnostic.swift` lines 21-22:

```swift
case .unsupportedExposedMethodSignature:
    return "@WireletExpose method parameter must be a primitive, String, @WireFormat type, or Optional / Array thereof."
```

- [ ] **Step 2: Remove the arity rejection in the macro**

Replace lines 33-50 of `Sources/WireletObservableMacros/WireletObservableMacro.swift` with:

```swift
// (no per-method diagnostic — the schema parser + classifier
// downstream accept any arity. Unrepresentable types surface as a
// compile error in the generated bridge.)
```

(i.e., delete the whole inner check — leave the `for member in ... { ... }` loop empty or remove it. Keep the surrounding `final` / `@Observable` checks.)

- [ ] **Step 3: Run the macro tests**

Run: `swift test --filter WireletObservableMacroTests`
Expected: most pass; the test `WireletObservableMacroDiagnostics.testUnsupportedExposedMethodSignatureRaisesDiagnostic` (or similarly named) fails because it expected a diagnostic that no longer fires.

- [ ] **Step 4: Update the macro test**

Open `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`, find the test that asserts a multi-arg `@WireletExpose` method emits `unsupportedExposedMethodSignature`. Replace it with a positive case:

```swift
@Test func multiArgExposedMethodIsAccepted() {
    assertMacroExpansion(
        """
        @WireletObservable
        @Observable
        final class Multi {
            @WireletExpose
            public func twoArgs(_ a: Int32, _ b: Int32) {}
        }
        """,
        expandedSource: """
        @Observable
        final class Multi {
            public func twoArgs(_ a: Int32, _ b: Int32) {}
        }
        """,
        diagnostics: [],
        macros: macroSpecs
    )
}
```

(The macro is marker-only; it does not emit code. Bridges come from the build tool plugin downstream.)

- [ ] **Step 5: Run macro tests**

Run: `swift test --filter WireletObservableMacro`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservableMacros/ Tests/WireletObservableMacrosTests/
git commit -m "feat(observable): accept multi-arg @WireletExpose methods at macro layer"
```

---

## Task 3: Multi-arg renderer in `InvokeBridgeEmitter`

**Files:**
- Modify: `Sources/WireletObservableSwiftBridgesEmitter/Internal/InvokeBridgeEmitter.swift`
- Modify: `Tests/WireletObservableSwiftBridgesEmitterTests/SwiftBridgesEmitterTests.swift` — add a multi-arg test before changing the renderer.

- [ ] **Step 1: Add the failing test**

Append to `Tests/WireletObservableSwiftBridgesEmitterTests/SwiftBridgesEmitterTests.swift`:

```swift
@Test func multiArgInvokeBridge() {
    let source = """
    import Observation
    import WireletObservable

    @WireletObservable
    @Observable
    public final class Demo {
        @WireletExpose
        public func setDone(_ id: Int32, _ done: Bool) {}
    }
    """
    let output = try! emit(source: source)
    let bridges = output.first(where: { $0.path.hasSuffix("Demo+JNIBridges.swift") })!.content

    #expect(bridges.contains("@_cdecl(\"WireletObservable_Demo_setDone_invoke\")"))
    #expect(bridges.contains("public func __Demo_setDone_invoke_jni("))
    #expect(bridges.contains("_ arg0: jint"))
    #expect(bridges.contains("_ arg1: jboolean"))
    #expect(bridges.contains("me.setDone(Int32(arg0), (arg1 != 0))"))
}
```

(Helper: a `emit(source:)` already exists in the test file. If not, copy-paste from another test fixture.)

- [ ] **Step 2: Run test, confirm failure**

Run: `swift test --filter multiArgInvokeBridge`
Expected: FAIL — the renderer returns `nil` for any method with more than one arg.

- [ ] **Step 3: Replace the renderer**

Rewrite `Sources/WireletObservableSwiftBridgesEmitter/Internal/InvokeBridgeEmitter.swift`:

```swift
import WireletObservableSchema

/// Renders `@WireletExpose` method invoke JNI bridge global functions.
///
/// Accepts any number of arguments whose types classify via
/// `InvokeArgClassifier`. Each arg crosses JNI as its native primitive
/// representation (`jint`, `jboolean`, etc.) or as `jbyteArray?` /
/// `jstring?` for types that need wire-format marshalling — there is no
/// hidden wrapper struct. See
/// `docs/superpowers/plans/2026-05-29-wirelet-observable-multi-arg-methods.md`.
enum InvokeBridgeEmitter {
    static func render(className: String, method: ObservableMethod) -> String? {
        let methodName = method.name
        let params = method.parameters

        if params.isEmpty {
            return renderZeroArg(className: className, methodName: methodName)
        }
        return renderNArg(className: className, methodName: methodName, params: params)
    }

    // MARK: - Zero-arg

    private static func renderZeroArg(className: String, methodName: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(methodName)()
        }
        """
    }

    // MARK: - N-arg

    private static func renderNArg(
        className: String,
        methodName: String,
        params: [ObservableMethodParameter]
    ) -> String {
        let paramList = params.enumerated().map { idx, p in
            "    _ arg\(idx): \(jniParameterType(for: p.typeText))"
        }.joined(separator: ",\n")

        let decodeBlocks = params.enumerated().compactMap { idx, p -> String? in
            decodeBlock(idx: idx, param: p)
        }.joined(separator: "\n    ")

        let callArgs = params.enumerated().map { idx, p in
            let value = "decoded\(idx)"
            return p.label == "_" ? value : "\(p.label): \(value)"
        }.joined(separator: ", ")

        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
        \(paramList)
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            \(decodeBlocks)
            me.\(methodName)(\(callArgs))
        }
        """
    }

    // MARK: - Per-arg JNI parameter type

    private static func jniParameterType(for typeText: String) -> String {
        switch InvokeArgClassifier.classify(typeText) {
        case .primitive(let jniSwiftType, _): return jniSwiftType
        case .bool:                           return "jboolean"
        case .string, .optionalString:        return "jstring?"
        case .wireFormat,
             .optionalPrimitive,
             .optionalWireFormat,
             .array:
            return "jbyteArray?"
        }
    }

    // MARK: - Per-arg decode block

    /// Returns a Swift statement that defines `decoded<idx>` from `arg<idx>`,
    /// or `nil` to abort the bridge silently on a decode failure. The
    /// statement embeds `guard` clauses that early-return — that's
    /// intentional so the parent bridge fails fast on malformed input.
    private static func decodeBlock(idx: Int, param: ObservableMethodParameter) -> String? {
        let argName = "arg\(idx)"
        let outName = "decoded\(idx)"
        switch InvokeArgClassifier.classify(param.typeText) {
        case .primitive(_, let swiftCast):
            return "let \(outName) = \(swiftCast)(\(argName))"
        case .bool:
            return "let \(outName) = (\(argName) != 0)"
        case .string:
            return """
            guard let env, let envValue = env.pointee, let raw\(idx) = \(argName) else {
                return
            }
            let cstr\(idx) = envValue.pointee.GetStringUTFChars(env, raw\(idx), nil)
            defer { envValue.pointee.ReleaseStringUTFChars(env, raw\(idx), cstr\(idx)) }
            guard let cstr\(idx) else {
                return
            }
            let \(outName) = String(cString: cstr\(idx))
            """
        case .wireFormat(let typeName):
            return """
            guard let env, let raw\(idx) = \(argName) else {
                return
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            guard let \(outName) = try? \(typeName)(decoding: data\(idx)) else {
                return
            }
            """
        case .optionalPrimitive(let inner):
            return """
            let \(outName): \(inner)?
            if let raw\(idx) = \(argName), let env {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(inner)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .optionalString:
            return """
            let \(outName): String?
            if let raw\(idx) = \(argName), let env, let envValue = env.pointee {
                let cstr\(idx) = envValue.pointee.GetStringUTFChars(env, raw\(idx), nil)
                defer { envValue.pointee.ReleaseStringUTFChars(env, raw\(idx), cstr\(idx)) }
                \(outName) = cstr\(idx).map { String(cString: $0) }
            } else {
                \(outName) = nil
            }
            """
        case .optionalWireFormat(let typeName):
            return """
            let \(outName): \(typeName)?
            if let raw\(idx) = \(argName), let env {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(typeName)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .array(let elementTypeName):
            return """
            guard let env, let raw\(idx) = \(argName) else {
                return
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            var reader\(idx) = WireFormatReader(data: data\(idx))
            guard let count\(idx) = try? reader\(idx).readVarint() else {
                return
            }
            var elements\(idx): [\(elementTypeName)] = []
            elements\(idx).reserveCapacity(Int(count\(idx)))
            for _ in 0..<Int(count\(idx)) {
                guard let element\(idx) = try? \(elementTypeName)(from: &reader\(idx)) else {
                    return
                }
                elements\(idx).append(element\(idx))
            }
            let \(outName) = elements\(idx)
            """
        }
    }
}
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter multiArgInvokeBridge`
Expected: PASS.

- [ ] **Step 5: Run the whole emitter test suite**

Run: `swift test --filter SwiftBridgesEmitter`
Expected: PASS, including the existing zero-arg and 1-arg `@WireFormat` snapshots. (The N-arg path covers N=1 wireformat correctly via the `.wireFormat` case.)

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservableSwiftBridgesEmitter/Internal/InvokeBridgeEmitter.swift \
        Tests/WireletObservableSwiftBridgesEmitterTests/SwiftBridgesEmitterTests.swift
git commit -m "feat(observable): emit native multi-arg invoke bridges via per-arg classifier"
```

---

## Task 4: Multi-arg Kotlin emitter

**Files:**
- Modify: `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift:160-205`
- Modify: `Tests/WireletObservableKotlinEmitterTests/ViewModelEmitterTests.swift` — add a multi-arg test.
- (Possibly) `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift` — needs a `kotlinTypeForInvokeArg(_:)` helper that maps Swift type text to Kotlin type (`Int32` → `Int`, `Bool` → `Boolean`, etc.). It may already exist as `ObservableKotlinTypeMap.plan(for:)`; check the file first.

- [ ] **Step 1: Find existing Kotlin type mapping**

Read `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift`. Look for a function that maps a property type to its Kotlin type. The setter path uses this. The invoke arg renderer below will reuse the same logic.

If the only mapping is via `Plan` (a property-focused struct), expose a thin static `kotlinType(forArgType:)` that takes `String` (e.g. `"Int32"`) and returns the Kotlin type string + the JNI external-fun parameter type. Implementation sketch:

```swift
extension ObservableKotlinTypeMap {
    static func invokeArg(forArgType swiftType: String, config: ObservableCodegenConfig) -> (kotlinType: String, externalFunType: String, encodeExpr: (String) -> String) {
        switch InvokeArgClassifier.classify(swiftType) {
        case .primitive(_, let cast):
            let kt = primitiveKotlinName(cast)
            return (kt, kt, { name in name })
        case .bool:
            return ("Boolean", "Boolean", { name in name })
        case .string:
            return ("String", "String", { name in name })
        case .wireFormat(let typeName):
            let kt = config.nameTransform.apply(to: typeName)
            let codec = kt + "Codec"
            return (kt, "ByteArray", { name in "\(codec).encode(\(name))" })
        // ...optional and array cases similarly...
        }
    }

    private static func primitiveKotlinName(_ swiftCast: String) -> String {
        switch swiftCast {
        case "Int8":  return "Byte"
        case "Int16": return "Short"
        case "Int32": return "Int"
        case "Int64": return "Long"
        case "UInt8", "UInt16": return "Int"  // widened
        case "UInt32", "UInt64": return "Long"
        case "Float":  return "Float"
        case "Double": return "Double"
        default: return swiftCast  // fallback; should not happen
        }
    }
}
```

This is the editable lookup table. Add only what's needed for the cases the macro can accept.

- [ ] **Step 2: Write the failing test**

Append to `Tests/WireletObservableKotlinEmitterTests/ViewModelEmitterTests.swift`:

```swift
@Test func multiArgInvokeEmission() throws {
    let vm = ObservableViewModel(
        name: "Demo",
        properties: [],
        methods: [
            ObservableMethod(
                name: "setDone",
                parameters: [
                    ObservableMethodParameter(label: "_", typeText: "Int32"),
                    ObservableMethodParameter(label: "_", typeText: "Bool"),
                ]
            ),
        ]
    )
    let output = ViewModelEmitter.emit(viewModel: vm, config: makeTestConfig())
    #expect(output.contains("fun setDone(arg0: Int, arg1: Boolean) ="))
    #expect(output.contains("nativeSetDone(nativePtr, arg0, arg1)"))
    #expect(output.contains("private external fun nativeSetDone(self: Long, arg0: Int, arg1: Boolean)"))
}
```

(Use whatever existing helper your tests use to build the config — `makeTestConfig()` is illustrative; check the file for the real builder.)

- [ ] **Step 3: Run, confirm failure**

Run: `swift test --filter multiArgInvokeEmission`
Expected: FAIL.

- [ ] **Step 4: Rewrite the invoke emission in `ViewModelEmitter`**

In `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift`, replace lines 160-205 (the function that returns `(publicFn, externalDecl, extraImports)`) with an N-arg variant:

```swift
private static func invokeMethod(
    method: ObservableMethod,
    config: ObservableCodegenConfig
) -> (publicFn: String, externalDecl: String, extraImports: Set<String>)? {
    let nativeFn = "native\(capitalised(method.name))"
    let params = method.parameters

    if params.isEmpty {
        let publicFn = """
            fun \(method.name)() = \(nativeFn)(nativePtr)
        """
        let external = "    private external fun \(nativeFn)(self: Long)"
        return (publicFn, external, [])
    }

    var argDecls: [String] = []
    var nativeArgs: [String] = []
    var externalParams: [String] = ["self: Long"]
    var imports: Set<String> = []

    for (idx, param) in params.enumerated() {
        let publicName = chooseArgName(param: param, idx: idx)
        let info = ObservableKotlinTypeMap.invokeArg(forArgType: param.typeText, config: config)
        argDecls.append("\(publicName): \(info.kotlinType)")
        nativeArgs.append(info.encodeExpr(publicName))
        externalParams.append("arg\(idx): \(info.externalFunType)")
        switch InvokeArgClassifier.classify(param.typeText) {
        case .wireFormat(let t),
             .optionalWireFormat(let t),
             .array(elementTypeName: let t):
            let kt = config.nameTransform.apply(to: t)
            imports.insert("\(config.modelPackage).\(kt)")
            imports.insert("\(config.codecPackage).\(kt)Codec")
        default: break
        }
    }

    let publicFn = """
        fun \(method.name)(\(argDecls.joined(separator: ", "))) =
            \(nativeFn)(nativePtr, \(nativeArgs.joined(separator: ", ")))
    """
    let external = "    private external fun \(nativeFn)(\(externalParams.joined(separator: ", ")))"
    return (publicFn, external, imports)
}

private static func chooseArgName(param: ObservableMethodParameter, idx: Int) -> String {
    if param.label != "_" { return param.label }
    if let internalName = param.internalName { return internalName }
    return "arg\(idx)"
}
```

(Match the surrounding code style — switch / if-else / etc. — and import `WireletObservableSchema` if it isn't already imported.)

- [ ] **Step 5: Run test**

Run: `swift test --filter multiArgInvokeEmission`
Expected: PASS.

- [ ] **Step 6: Run the full Kotlin emitter suite**

Run: `swift test --filter WireletObservableKotlinEmitter`
Expected: PASS — the existing golden files (Counter, TodoList) should still match because the N-arg path covers N=1 wireformat correctly. If a golden file diffs, inspect carefully: the public-function indentation must remain stable. If the diff is whitespace-only and looks correct, update the fixture.

- [ ] **Step 7: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/ \
        Tests/WireletObservableKotlinEmitterTests/
git commit -m "feat(observable): emit multi-arg Kotlin invoke wrappers + external fun decls"
```

---

## Task 5: Multi-arg JNI signature in sidecar builder

**Files:**
- Modify: `Sources/WireletObservableKotlinEmitter/JNISidecarBuilder.swift:151-178`
- Add: a multi-arg test in `Tests/WireletObservableKotlinEmitterTests/JNISidecarBuilderTests.swift` (create the test file if it doesn't exist).

- [ ] **Step 1: Locate or create the sidecar test file**

Run: `ls Tests/WireletObservableKotlinEmitterTests/`
If a sidecar test file exists, use it. Otherwise create `Tests/WireletObservableKotlinEmitterTests/JNISidecarBuilderTests.swift` with:

```swift
import Testing
@testable import WireletObservableKotlinEmitter
@testable import WireletObservableSchema

@Suite struct JNISidecarBuilderTests {
    @Test func multiArgSignature() throws {
        let vm = ObservableViewModel(
            name: "Demo",
            properties: [],
            methods: [
                ObservableMethod(
                    name: "setDone",
                    parameters: [
                        ObservableMethodParameter(label: "_", typeText: "Int32"),
                        ObservableMethodParameter(label: "_", typeText: "Bool"),
                    ]
                ),
                ObservableMethod(
                    name: "render",
                    parameters: [
                        ObservableMethodParameter(label: "_", typeText: "Int32"),
                        ObservableMethodParameter(label: "_", typeText: "TodoItem"),
                    ]
                ),
            ]
        )
        let config = makeConfig()
        let registration = try JNISidecarBuilder.build(viewModels: [vm], config: config)
            .viewModels.first!
        let setDone = registration.nativeMethods.first { $0.name == "nativeSetDone" }!
        let render = registration.nativeMethods.first { $0.name == "nativeRender" }!
        #expect(setDone.signature == "(JIZ)V")
        #expect(render.signature == "(JI[B)V")
    }
}
```

(Reuse `makeConfig()` from neighbouring tests; if not available, declare a minimal one inline.)

- [ ] **Step 2: Run, confirm failure**

Run: `swift test --filter JNISidecarBuilder`
Expected: FAIL — current `methodEntry` returns `nil` for `>1` args, so the methods don't even appear in the registration.

- [ ] **Step 3: Replace `methodEntry` with N-arg signature**

In `Sources/WireletObservableKotlinEmitter/JNISidecarBuilder.swift`, replace the `methodEntry` function (lines ~151-178) with:

```swift
private static func methodEntry(
    method: ObservableMethod,
    vmName: String,
    config: ObservableCodegenConfig
) -> JNISidecarNativeMethod? {
    let nativeName = "native\(capitalised(method.name))"
    let cdecl = "WireletObservable_\(vmName)_\(method.name)_invoke"
    let argDescriptors = method.parameters
        .map { jniDescriptor(forArgType: $0.typeText) }
        .joined()
    return JNISidecarNativeMethod(
        name: nativeName,
        signature: "(J\(argDescriptors))V",
        cdeclSymbol: cdecl
    )
}

/// JNI descriptor for one method-arg type (no `J` self prefix, no return).
private static func jniDescriptor(forArgType swiftType: String) -> String {
    switch InvokeArgClassifier.classify(swiftType) {
    case .primitive(let jniSwiftType, _):
        switch jniSwiftType {
        case "jint":     return "I"
        case "jlong":    return "J"
        case "jfloat":   return "F"
        case "jdouble":  return "D"
        case "jboolean": return "Z"  // unreachable here (bool case handles it)
        default: return "[B"
        }
    case .bool:                                  return "Z"
    case .string, .optionalString:               return "Ljava/lang/String;"
    case .wireFormat,
         .optionalPrimitive,
         .optionalWireFormat,
         .array:
        return "[B"
    }
}
```

- [ ] **Step 4: Run sidecar tests**

Run: `swift test --filter JNISidecarBuilder`
Expected: PASS.

- [ ] **Step 5: Verify existing single-arg sidecar sigs unchanged**

Run: `swift test --filter WireletObservableKotlinEmitter`
Expected: PASS — the `add(_ item: TodoItem)` golden case still produces `(J[B)V`.

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/JNISidecarBuilder.swift \
        Tests/WireletObservableKotlinEmitterTests/
git commit -m "feat(observable): build multi-arg JNI signatures from per-arg descriptors"
```

---

## Task 6: End-to-end example — `setDone(id:done:)` + interactive checkbox

**Files:**
- Modify: `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift`
- Modify: `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoScreen.kt`
- (No new tests; the existing `TodoBurstInstrumentedTest` continues to cover the burst path.)

- [ ] **Step 1: Add `setDone(_:_:)` to the Swift VM**

Insert into `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift`, immediately after `add(_:)`:

```swift
    @WireletExpose
    public func setDone(_ id: Int32, _ done: Bool) {
        items = items.map {
            $0.id == id
                ? TodoItem(id: $0.id, title: $0.title, done: done)
                : $0
        }
    }
```

- [ ] **Step 2: Update Compose UI**

In `TodoScreen.kt`, replace the existing `Checkbox(checked = item.done, onCheckedChange = null)` line with:

```kotlin
Checkbox(
    checked = item.done,
    onCheckedChange = { newDone -> viewModel.setDone(item.id, newDone) },
)
```

- [ ] **Step 3: Republish wirelet artifacts**

Run:
```bash
/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/kotlin/gradlew \
  -p /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/kotlin \
  -PwireletVersion=0.0.1-local \
  :runtime:publishToMavenLocal \
  :observable-runtime:publishToMavenLocal \
  :gradle-plugin:publishToMavenLocal
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Cross-compile the Swift .so**

Run:
```bash
swift build \
  --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/swift \
  --swift-sdk aarch64-unknown-linux-android28 \
  -c release
```
Expected: `Build complete!`.

- [ ] **Step 5: Verify the new JNI symbol**

Run:
```bash
$HOME/Library/Android/sdk/ndk/26.1.10909125/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm \
  -D --defined-only \
  /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/swift/.build/aarch64-unknown-linux-android28/release/libObservableCounterJNI.so \
  | grep WireletObservable_TodoListVM_setDone
```
Expected: a single line ending in `WireletObservable_TodoListVM_setDone_invoke`.

- [ ] **Step 6: Stage the .so**

Run:
```bash
cp /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/swift/.build/aarch64-unknown-linux-android28/release/libObservableCounterJNI.so \
   /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/android-app/app/src/main/jniLibs/arm64-v8a/
```

- [ ] **Step 7: Build the APK**

Run:
```bash
/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/android-app/gradlew \
  -p /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/android-app \
  :app:assembleDebug
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Run the burst test (regression check)**

```bash
ANDROID_SERIAL=<your-device-serial> \
  /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/android-app/gradlew \
  -p /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/android-app \
  :app:connectedDebugAndroidTest
```
Expected: `addBurstReachesExpectedSnapshot` PASS (the new method doesn't affect that flow).

- [ ] **Step 9: Manual checkbox smoke**

Install + launch the app (`gradlew :app:installDebug` + `adb shell am start -n io.github.jiyimeta.observablecounter/.MainActivity`). Tap **Add** a few times, then toggle one of the checkboxes. Expected: the tapped row's checkbox flips state and stays flipped (Compose recomposes when the underlying `StateFlow<List<TodoItem>>` emits a new list). Tap **Clear**; the list empties.

- [ ] **Step 10: Commit**

```bash
git add examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift \
        examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoScreen.kt
git commit -m "feat(observable-counter): interactive checkbox via setDone(id:done:) multi-arg method"
```

---

## Task 7: Docs + retrospective

**Files:**
- Modify: `docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md`
- Modify: `Sources/WireletObservableSchema/ObservableSchema.swift:94-97` — drop the "exactly two shapes" doc comment claim.

- [ ] **Step 1: Update the Phase 4 retrospective**

Append a new section to the retrospective in
`docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md` (after the existing follow-up notes):

```markdown
### Multi-arg `@WireletExpose` method support (post-Phase 4 follow-up)

The Phase 1 restriction "zero-arg OR single `@WireFormat` arg" was lifted.
`@WireletExpose` now accepts any number of arguments mixing primitive,
`String`, `@WireFormat`, `Optional`, and `Array` types. Each arg crosses
JNI in its natural form (primitives as native `jint`/`jboolean`/…, strings
as `jstring?`, wire-format types as `jbyteArray?`). No hidden wrapper
struct; Kotlin allocates only when an arg's wire format requires it
(byte arrays for `@WireFormat`/`Optional`/`Array`).

See `docs/superpowers/plans/2026-05-29-wirelet-observable-multi-arg-methods.md`
for the implementation plan. The example app's checkbox toggle exercises
this via `setDone(_ id: Int32, _ done: Bool)`.
```

- [ ] **Step 2: Refresh the schema doc comment**

In `Sources/WireletObservableSchema/ObservableSchema.swift` (around line 94), replace:

```swift
    /// At v0.1 we support exactly two shapes: zero parameters, or one
    /// parameter whose type is a `@WireFormat` user type. Both forms are
    /// recorded as the parameter list as it appears in source — the
    /// emitter validates the shape.
```

with:

```swift
    /// Parameter list as it appears in source. Any number of parameters
    /// is accepted; the bridge emitters validate the per-parameter types
    /// via `InvokeArgClassifier`. Unrepresentable types surface as a
    /// compile error in the generated bridge.
```

- [ ] **Step 3: Open the plan in QuickMD per project convention**

Run: `quick-md /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/docs/superpowers/plans/2026-05-29-wirelet-observable-multi-arg-methods.md`
Expected: QuickMD opens the file in the rendered viewer (no console output).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md \
        Sources/WireletObservableSchema/ObservableSchema.swift
git commit -m "docs(observable): note multi-arg method support in Phase 4 retrospective"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run the full Swift test suite**

Run: `swift test`
Expected: 100% pass (existing 101 + the new `InvokeArgClassifierTests` ≈10 + multiArg fixture tests ≈3 = ~114 total).

- [ ] **Step 2: Run the full Kotlin check suite**

Run:
```bash
/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/kotlin/gradlew \
  -p /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/kotlin \
  check
```
Expected: `BUILD SUCCESSFUL`. Functional + conformance + emitter all pass.

- [ ] **Step 3: Confirm `.so` symbols on a clean build**

```bash
swift build \
  --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/swift \
  --swift-sdk aarch64-unknown-linux-android28 \
  -c release
```

```bash
$HOME/Library/Android/sdk/ndk/26.1.10909125/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm \
  -D --defined-only \
  /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet/.claude/worktrees/observable-bridge/examples/observable-counter/swift/.build/aarch64-unknown-linux-android28/release/libObservableCounterJNI.so \
  | grep -E "JNI_OnLoad|WireletObservable_TodoListVM_" | wc -l
```
Expected: `12` (10 existing bridges + 1 `setDone` + 1 `JNI_OnLoad`).

- [ ] **Step 4: No commit**

Verification only.

---

## Self-review checklist

- [x] **Spec coverage** — every section in the architecture maps to a task: classifier (Task 1), macro relaxation (Task 2), Swift bridges (Task 3), Kotlin emitter (Task 4), JNI sidecar (Task 5), end-to-end smoke (Task 6), docs (Task 7), verification (Task 8). Out-of-scope items (throws, return values, default args) are explicitly listed.
- [x] **Placeholder scan** — no "TBD" / "implement details" / "add edge cases" — every code block is complete. The only "look at the file" references are for verifying existing helper names in `ObservableKotlinTypeMap` (Task 4 Step 1) and the sidecar test scaffold (Task 5 Step 1) — both are stated as concrete checks, not unspecified work.
- [x] **Type consistency** — `InvokeArgKind` cases use consistent names across Tasks 1-5. `InvokeArgClassifier.classify(_:)` is referenced identically everywhere. Function names `invokeMethod`, `methodEntry`, `decodeBlock`, `jniDescriptor(forArgType:)` are each defined in exactly one task and reused unchanged later.
- [x] **Bite-size granularity** — every task ends in one commit; every step is 2-5 minutes; failing tests come before implementation; final verification has no commit.

---

## What lands after this plan

- Phase 5 unblocks: `wirelet-observable-runtime` ships with multi-arg-method support, so the v0.2.0 surface is meaningfully more useful for real Compose consumers.
- The next deferred item is **diff-based `Array<T>` updates** (`WireletListDiff` codec) — orthogonal to method arity, surfaces only when consumers hit big-list re-encode cost.
- A future `@WireletExpose(fastPath: true)` opt-in could bypass even the per-arg JNI overhead for kHz+ real-time methods (audio threads). Not needed for v0.2.
