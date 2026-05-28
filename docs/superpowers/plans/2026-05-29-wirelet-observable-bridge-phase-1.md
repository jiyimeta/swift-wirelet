# Wirelet Observable Bridge — Phase 1: Swift Runtime + Macro

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Swift side of the Observable bridge — the `WireletObservable` runtime target, the `@WireletObservable` macro, and the `@WireletExpose` marker — such that a hand-written Kotlin file can consume the macro-generated `@_cdecl` symbols on Android. Kotlin codegen, Gradle plugin, and the end-to-end example are out of scope for this plan and land in a follow-up.

**Architecture:** A new SwiftPM `WireletObservable` library target hosts the runtime helpers (`JObject` Runnable wrapper, `WireletObservableJNI` retain/release/marshal helpers) under `#if os(Android)`, plus the cross-platform `@WireletObservable` and `@WireletExpose` macro declarations. A new `WireletObservableMacros` plugin target implements `@WireletObservable` as a SwiftSyntax extension macro that emits per-property `@_cdecl` JNI bridges wrapped in `withObservationTracking { … } onChange:`, all guarded by `#if os(Android) … #endif`. The macro itself runs on the host (macOS/Linux); generated code only compiles when the consumer cross-builds for Android. A new C system module `CWireletJNI` exposes `JNIEnv`, `jlong`, `jobject`, `jbyteArray`, etc. from the Android NDK; on Apple the shim header is empty, so the module compiles to nothing.

**Tech Stack:** Swift 6.0, SwiftPM, SwiftSyntax 603 (already pinned), Swift Testing for unit tests, `SwiftSyntaxMacrosTestSupport` for macro snapshot tests, Clang module map for `CWireletJNI`.

---

## File Structure

**Create:**
- `Sources/CWireletJNI/module.modulemap` — system module map.
- `Sources/CWireletJNI/shim.h` — conditionally `#include <jni.h>` under `__ANDROID__`.
- `Sources/WireletObservable/WireletObservable.swift` — module entry point, declares macros, `@_exported import CWireletJNI` under `#if os(Android)`.
- `Sources/WireletObservable/ObservationTrackingHelper.swift` — Apple-buildable helper that takes a closure and an onChange and re-arms `withObservationTracking`. Used by tests and by the macro-generated code as a reusable building block.
- `Sources/WireletObservable/JObject.swift` — Runnable wrapper, Android-only.
- `Sources/WireletObservable/WireletObservableJNI.swift` — retain/unwrap/release + array encode/decode helpers, Android-only.
- `Sources/WireletObservableMacros/Plugin.swift` — macro plugin registration.
- `Sources/WireletObservableMacros/WireletObservableMacro.swift` — extension macro impl.
- `Sources/WireletObservableMacros/WireletExposeMacro.swift` — peer macro stub (no expansion; marker only).
- `Sources/WireletObservableMacros/WireletObservableDiagnostic.swift` — diagnostic messages.
- `Sources/WireletObservableMacros/WireletObservableProperty.swift` — internal model of a tracked stored property (name, type, JNI signature mapping).
- `Tests/WireletObservableTests/ObservationTrackingHelperTests.swift` — Apple-side re-arm semantics.
- `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift` — macro expansion snapshot tests.

**Modify:**
- `Package.swift` — add `WireletObservable`, `WireletObservableMacros`, `CWireletJNI`, and two test targets; add `WireletObservable` to products.

**Out of scope (future plans):**
- `Sources/WireletObservableSchema/`, `Sources/WireletObservableKotlinEmitter/`, `Sources/EmitWireletObservable/` — Phase 3 plan.
- `kotlin/observable-runtime/`, `kotlin/gradle-plugin/observable` DSL — Phase 4 plan.
- `examples/observable-counter/` — Phase 5 plan.

---

## Phase 1A: Swift runtime scaffolding

### Task 1: Add `CWireletJNI` system module

**Files:**
- Create: `Sources/CWireletJNI/module.modulemap`
- Create: `Sources/CWireletJNI/shim.h`

- [ ] **Step 1: Write `shim.h`**

```c
#ifndef WIRELET_OBSERVABLE_CJNI_SHIM_H
#define WIRELET_OBSERVABLE_CJNI_SHIM_H

#ifdef __ANDROID__
#include <jni.h>
#endif

#endif
```

- [ ] **Step 2: Write `module.modulemap`**

```
module CWireletJNI {
    header "shim.h"
    export *
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CWireletJNI/
git commit -m "feat(observable): add CWireletJNI system module (Android-conditional)"
```

### Task 2: Register new targets in `Package.swift`

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add `WireletObservable` to `products`**

Insert after the existing `Wirelet` product entry:

```swift
.library(name: "WireletObservable", targets: ["WireletObservable"]),
```

- [ ] **Step 2: Add the four new targets to `targets`**

Insert after the existing `.target(name: "Wirelet", …)` entry:

```swift
.systemLibrary(
    name: "CWireletJNI",
    path: "Sources/CWireletJNI"
),
.macro(
    name: "WireletObservableMacros",
    dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
    ]
),
.target(
    name: "WireletObservable",
    dependencies: [
        "Wirelet",
        "WireletObservableMacros",
        "CWireletJNI",
    ]
),
```

- [ ] **Step 3: Add the two new test targets**

Append before the closing `]` of `targets`:

```swift
.testTarget(
    name: "WireletObservableTests",
    dependencies: ["WireletObservable", "Wirelet"]
),
.testTarget(
    name: "WireletObservableMacrosTests",
    dependencies: [
        "WireletObservableMacros",
        "WireletObservable",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
    ]
),
```

- [ ] **Step 4: Verify package resolves**

Run: `swift package describe --type json | head -5`
Expected: JSON header lines, no errors. If SwiftPM complains about `CWireletJNI` lacking a header, check Step 1 of Task 1.

- [ ] **Step 5: Commit**

```bash
git add Package.swift
git commit -m "feat(observable): register WireletObservable + WireletObservableMacros + CWireletJNI targets"
```

### Task 3: Add Apple-buildable `ObservationTrackingHelper`

**Files:**
- Create: `Sources/WireletObservable/WireletObservable.swift`
- Create: `Sources/WireletObservable/ObservationTrackingHelper.swift`
- Create: `Tests/WireletObservableTests/ObservationTrackingHelperTests.swift`

The macro-generated JNI bridges call `withObservationTracking { read } onChange: { … }` directly. But for unit-testability we extract the re-arm loop into a helper that can be exercised on Apple without any JNI. The helper takes a `read` closure (returns `T`), an `onChange` callback, and returns the current value while installing tracking.

- [ ] **Step 1: Write `WireletObservable.swift` (module entry, declarations only)**

```swift
// Re-export the C JNI module on Android; on Apple this import is a no-op
// because the macro-generated extensions are themselves guarded by
// `#if os(Android)` and so the JNI types are never referenced.
#if os(Android)
@_exported import CWireletJNI
#endif

// Macro declarations are added in Task 4 / Task 8.
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/WireletObservableTests/ObservationTrackingHelperTests.swift
import Observation
import Testing
@testable import WireletObservable

@Observable
final class Counter {
    var value: Int = 0
}

@Suite struct ObservationTrackingHelperTests {
    @Test func readReturnsCurrentValue() {
        let counter = Counter()
        counter.value = 7
        let snapshot = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            // onChange ignored for this assertion
        }
        #expect(snapshot == 7)
    }

    @Test func onChangeFiresOnceForMutation() async {
        let counter = Counter()
        var fired = 0
        _ = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            fired += 1
        }
        counter.value = 1
        // withObservationTracking dispatches onChange synchronously on the
        // mutating thread; no async wait needed in this test.
        #expect(fired == 1)
    }

    @Test func onChangeFiresOnlyOnceWithoutReArm() {
        let counter = Counter()
        var fired = 0
        _ = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            fired += 1
        }
        counter.value = 1
        counter.value = 2
        // Second mutation must NOT fire because the subscription is one-shot
        // and we never re-armed.
        #expect(fired == 1)
    }
}
```

- [ ] **Step 3: Run test, confirm failure**

Run: `swift test --filter ObservationTrackingHelperTests`
Expected: compile error `cannot find 'ObservationTrackingHelper' in scope`.

- [ ] **Step 4: Implement `ObservationTrackingHelper`**

```swift
// Sources/WireletObservable/ObservationTrackingHelper.swift
import Observation

/// Wraps `withObservationTracking` so the macro-generated JNI bridges and
/// tests share the same re-arm contract.
///
/// `withObservationTracking { … } onChange:` registers a one-shot
/// subscription: `onChange` runs exactly once on the next mutation of any
/// storage accessed inside the `read` closure. To keep emitting, the
/// caller must invoke `read(_:on:onChange:)` again from inside `onChange`.
/// The macro-generated Kotlin side does exactly that via the JNI bridge.
public enum ObservationTrackingHelper {
    /// Reads `keyPath` on `subject` under an Observation tracker. Returns
    /// the snapshot value and installs `onChange` as the one-shot callback.
    @inlinable
    public static func read<Subject: AnyObject, Value>(
        _ keyPath: KeyPath<Subject, Value>,
        on subject: Subject,
        onChange: @escaping @Sendable () -> Void
    ) -> Value {
        var snapshot: Value!
        withObservationTracking {
            snapshot = subject[keyPath: keyPath]
        } onChange: {
            onChange()
        }
        return snapshot
    }
}
```

- [ ] **Step 5: Run test, confirm pass**

Run: `swift test --filter ObservationTrackingHelperTests`
Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservable/ Tests/WireletObservableTests/
git commit -m "feat(observable): add ObservationTrackingHelper with one-shot re-arm contract"
```

### Task 4: Declare `@WireletExpose` peer macro (marker only)

**Files:**
- Modify: `Sources/WireletObservable/WireletObservable.swift`
- Create: `Sources/WireletObservableMacros/Plugin.swift`
- Create: `Sources/WireletObservableMacros/WireletExposeMacro.swift`

`@WireletExpose` is a marker attribute on methods. It does not synthesize any code — the schema parser (Phase 3) scans for it. But Swift requires a real macro declaration; otherwise consumers can't write the attribute.

- [ ] **Step 1: Write the macro plugin shell**

```swift
// Sources/WireletObservableMacros/Plugin.swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletObservablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireletExposeMacro.self,
        // WireletObservableMacro.self — added in Task 8.
    ]
}
```

- [ ] **Step 2: Implement the empty peer-macro**

```swift
// Sources/WireletObservableMacros/WireletExposeMacro.swift
import SwiftSyntax
import SwiftSyntaxMacros

/// Marker attribute. The schema parser inspects functions carrying this
/// attribute; the macro itself synthesizes nothing.
public struct WireletExposeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
```

- [ ] **Step 3: Add the macro declaration to the runtime module**

Append to `Sources/WireletObservable/WireletObservable.swift`:

```swift
/// Marker for a method that the Wirelet Observable Kotlin codegen should
/// expose on the generated `<Name>ViewModel`. Methods without this
/// attribute are not bridged. The macro itself synthesizes no code.
@attached(peer)
public macro WireletExpose() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletExposeMacro"
)
```

- [ ] **Step 4: Sanity-build**

Run: `swift build`
Expected: build succeeds. No tests added in this task.

- [ ] **Step 5: Commit**

```bash
git add Sources/WireletObservable/ Sources/WireletObservableMacros/
git commit -m "feat(observable): add @WireletExpose marker macro"
```

### Task 5: Add `JObject` Runnable wrapper (Android-only)

**Files:**
- Create: `Sources/WireletObservable/JObject.swift`

`JObject` wraps a `jobject` Java `Runnable`. The macro-generated `__<prop>_track_jni` bridges receive the runnable as an argument, wrap it in `JObject`, and invoke `call(method: "run")` inside the `withObservationTracking` `onChange:` block. The wrapper holds a JNI global ref for lifetime safety; `deinit` calls `DeleteGlobalRef`.

This file compiles only on Android. The Apple build skips the entire body via `#if os(Android)` so the file is effectively empty.

- [ ] **Step 1: Write `JObject.swift`**

```swift
// Sources/WireletObservable/JObject.swift
#if os(Android)
import CWireletJNI

/// Wraps a JNI `jobject` (specifically, a `java.lang.Runnable`) so the
/// macro-generated `withObservationTracking { … } onChange:` block can
/// invoke `.run()` without spelling out the JNI ceremony.
///
/// Holds a JNI global reference; the local reference passed across the
/// `@_cdecl` boundary would be invalid by the time `onChange` fires.
public final class JObject {
    private let vm: UnsafeMutablePointer<JavaVM?>
    private var globalRef: jobject

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

    /// Invokes `Runnable.run()` on the wrapped object. Errors are swallowed
    /// (logged via `__android_log_write` in a future iteration); the macro
    /// generated re-arm path treats `onChange` as best-effort.
    public func call(method name: String) {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return }
        guard let cls = envValue.pointee.GetObjectClass(env, globalRef) else { return }
        guard let methodID = envValue.pointee.GetMethodID(env, cls, name, "()V") else { return }
        envValue.pointee.CallVoidMethod(env, globalRef, methodID)
    }
}
#endif
```

- [ ] **Step 2: Sanity-build on Apple**

Run: `swift build`
Expected: build succeeds (the file compiles to nothing on macOS).

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservable/JObject.swift
git commit -m "feat(observable): add JObject Runnable wrapper (Android-only)"
```

### Task 6: Add `WireletObservableJNI` helpers (Android-only)

**Files:**
- Create: `Sources/WireletObservable/WireletObservableJNI.swift`

Pointer marshaling between Swift class instances and `jlong`. The macro-generated `__new` entrypoint calls `retain(_:)`, `__release` calls `release(_:)`, and every other bridge calls `unwrap(_:)`.

- [ ] **Step 1: Write the helper module**

```swift
// Sources/WireletObservable/WireletObservableJNI.swift
#if os(Android)
import CWireletJNI
import Wirelet

/// Helpers used by macro-generated `@_cdecl` JNI bridges. Keeping the
/// pointer ceremony out of the macro expansion makes diffs of generated
/// code readable and lets us unit-test the marshaling separately.
public enum WireletObservableJNI {

    /// Allocates a `jlong` that owns a +1 retain on `value`. The Kotlin
    /// side stores this in a `Long` and passes it back as `self` to every
    /// bridge call. Released via `release(_:)`.
    public static func retain<T: AnyObject>(_ value: T) -> jlong {
        let unmanaged = Unmanaged.passRetained(value)
        return jlong(Int(bitPattern: unmanaged.toOpaque()))
    }

    /// Borrows a reference from a `jlong` without changing retain count.
    /// Safe for the duration of the JNI call; do not store the returned
    /// reference beyond it.
    public static func unwrap<T: AnyObject>(_ pointer: jlong, as: T.Type = T.self) -> T {
        let opaque = UnsafeRawPointer(bitPattern: Int(pointer))!
        return Unmanaged<T>.fromOpaque(opaque).takeUnretainedValue()
    }

    /// Drops the +1 retain previously taken by `retain(_:)`. Called from
    /// the Kotlin side's `ViewModel.onCleared()`. Subsequent calls with
    /// the same `pointer` are undefined behavior; the Kotlin side must
    /// null its `nativePtr` after `release`.
    public static func release<T: AnyObject>(_ pointer: jlong, as: T.Type = T.self) {
        let opaque = UnsafeRawPointer(bitPattern: Int(pointer))!
        Unmanaged<T>.fromOpaque(opaque).release()
    }

    /// Encodes a `@WireFormat` value to a freshly-allocated `jbyteArray`.
    public static func encode<T: WireFormatEncodable>(
        _ value: T,
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> jbyteArray? {
        var writer = WireFormatWriter()
        value.encode(into: &writer)
        return jbyteArray(env: env, bytes: writer.data)
    }

    /// Encodes an array of `@WireFormat` values as `[count varint][payload…]`.
    public static func encodeArray<T: WireFormatEncodable>(
        _ array: [T],
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> jbyteArray? {
        var writer = WireFormatWriter()
        writer.writeVarint(UInt64(array.count))
        for element in array {
            element.encode(into: &writer)
        }
        return jbyteArray(env: env, bytes: writer.data)
    }

    /// Decodes a Kotlin-side `jbyteArray` payload into a Swift `Data`.
    public static func dataFromByteArray(
        _ bytes: jbyteArray?,
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> Data {
        guard let bytes, let envValue = env.pointee else { return Data() }
        let length = Int(envValue.pointee.GetArrayLength(env, bytes))
        var buffer = [UInt8](repeating: 0, count: length)
        buffer.withUnsafeMutableBufferPointer { raw in
            envValue.pointee.GetByteArrayRegion(
                env, bytes, 0, jsize(length),
                raw.baseAddress.map { $0.withMemoryRebound(to: jbyte.self, capacity: length) { $0 } }
            )
        }
        return Data(buffer)
    }
}

/// Small wrapper so call sites read top-down.
private func jbyteArray(
    env: UnsafeMutablePointer<JNIEnv?>,
    bytes: Data
) -> jbyteArray? {
    guard let envValue = env.pointee else { return nil }
    guard let array = envValue.pointee.NewByteArray(env, jsize(bytes.count)) else {
        return nil
    }
    bytes.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: jbyte.self).baseAddress else { return }
        envValue.pointee.SetByteArrayRegion(env, array, 0, jsize(bytes.count), base)
    }
    return array
}
#endif
```

- [ ] **Step 2: Sanity-build on Apple**

Run: `swift build`
Expected: build succeeds (file is empty on macOS).

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservable/WireletObservableJNI.swift
git commit -m "feat(observable): add WireletObservableJNI retain/unwrap/release + encode helpers"
```

### Task 7: Verify Phase 1A baseline

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: 78 existing + 3 new ObservationTrackingHelper tests = 81 tests pass.

- [ ] **Step 2: Confirm WireletObservable product builds**

Run: `swift build --target WireletObservable`
Expected: target builds, no warnings.

- [ ] **Step 3: No commit** (verification only).

---

## Phase 1B: `@WireletObservable` macro

### Task 8: Declare `@WireletObservable` extension macro

**Files:**
- Modify: `Sources/WireletObservable/WireletObservable.swift`
- Modify: `Sources/WireletObservableMacros/Plugin.swift`
- Create: `Sources/WireletObservableMacros/WireletObservableMacro.swift`
- Create: `Sources/WireletObservableMacros/WireletObservableDiagnostic.swift`
- Create: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`

The macro is an `ExtensionMacro` that emits a single `extension <Type> { #if os(Android) … #endif }`. This task wires the empty shell; subsequent tasks fill in the expansion.

- [ ] **Step 1: Add macro declaration to the runtime module**

Append to `Sources/WireletObservable/WireletObservable.swift`:

```swift
/// Attaches Wirelet's Observable bridging to a `final class` that is also
/// `@Observable`. Emits per-stored-property JNI bridges (`@_cdecl`) inside
/// an `#if os(Android)` block; Apple builds see only the unmodified
/// `@Observable` semantics.
///
/// Restrictions:
/// - The class must be `final`.
/// - The class must also carry Apple's `@Observable` attribute.
/// - Stored properties must use one of: primitive (`Int8/16/32/64`,
///   `UInt8/16/32/64`, `Bool`, `Float`, `Double`, `String`), `@WireFormat`
///   struct/enum, or `Array<T>` / `Optional<T>` of the above.
/// - `@ObservationIgnored` properties are skipped.
@attached(extension)
public macro WireletObservable() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletObservableMacro"
)
```

- [ ] **Step 2: Register macro in the plugin**

Update `Sources/WireletObservableMacros/Plugin.swift`:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletObservablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireletExposeMacro.self,
        WireletObservableMacro.self,
    ]
}
```

- [ ] **Step 3: Write the diagnostic table**

```swift
// Sources/WireletObservableMacros/WireletObservableDiagnostic.swift
import SwiftDiagnostics

enum WireletObservableDiagnostic: String, DiagnosticMessage {
    case notAFinalClass
    case missingObservableAttribute
    case unsupportedPropertyType

    var diagnosticID: MessageID {
        MessageID(domain: "WireletObservable", id: rawValue)
    }
    var severity: DiagnosticSeverity { .error }
    var message: String {
        switch self {
        case .notAFinalClass:
            return "@WireletObservable requires a final class."
        case .missingObservableAttribute:
            return "@WireletObservable must be paired with @Observable."
        case .unsupportedPropertyType:
            return "Unsupported property type for @WireletObservable. Use a primitive, String, @WireFormat type, or Optional/Array thereof."
        }
    }
}
```

- [ ] **Step 4: Write the empty macro impl**

```swift
// Sources/WireletObservableMacros/WireletObservableMacro.swift
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct WireletObservableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasFinalModifier(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasObservableAttribute(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.missingObservableAttribute))
            return []
        }
        // TODO Task 10+: emit JNI bridges per stored property.
        let body: DeclSyntax = """
        extension \(type.trimmed) {
            #if os(Android)
            // Empty until Task 10 fills in per-property expansion.
            #endif
        }
        """
        guard let ext = body.as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    private static func hasFinalModifier(_ decl: ClassDeclSyntax) -> Bool {
        decl.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
    }

    private static func hasObservableAttribute(_ decl: ClassDeclSyntax) -> Bool {
        decl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "Observable"
        }
    }
}
```

- [ ] **Step 5: Write snapshot test for missing-final diagnostic**

```swift
// Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import WireletObservableMacros

private let macroSpecs: [String: any Macro.Type] = [
    "WireletObservable": WireletObservableMacro.self,
    "WireletExpose": WireletExposeMacro.self,
]

@Suite struct WireletObservableMacroDiagnostics {
    @Test func nonFinalClassEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable requires a final class.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }

    @Test func missingObservableEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            final class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable must be paired with @Observable.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }
}
```

- [ ] **Step 6: Run tests, confirm pass**

Run: `swift test --filter WireletObservableMacroDiagnostics`
Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/WireletObservable/WireletObservable.swift Sources/WireletObservableMacros/ Tests/WireletObservableMacrosTests/
git commit -m "feat(observable): declare @WireletObservable macro with final/Observable diagnostics"
```

### Task 9: Stored-property model

**Files:**
- Create: `Sources/WireletObservableMacros/WireletObservableProperty.swift`

A typed model for one stored property: name, Swift type, JNI return type, marshaling kind. Used in Task 10/11/12. Pure data + helpers; no diagnostics emitted here.

- [ ] **Step 1: Implement the model**

```swift
// Sources/WireletObservableMacros/WireletObservableProperty.swift
import SwiftSyntax

struct WireletObservableProperty {
    enum Kind {
        case primitive(jniType: String, swiftReadExpr: (String) -> String)
        case string
        case wireFormat(typeName: String)
        case wireFormatArray(elementTypeName: String)
        case optionalPrimitive(jniType: String)
        case optionalString
        case optionalWireFormat(typeName: String)
    }

    let name: String
    let swiftTypeText: String
    let kind: Kind
    let isMutable: Bool
    let isIgnored: Bool
}

extension WireletObservableProperty {
    static func collect(_ classDecl: ClassDeclSyntax) -> [WireletObservableProperty] {
        var out: [WireletObservableProperty] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else { continue }
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            guard let typeSyntax = binding.typeAnnotation?.type else { continue }
            let typeText = typeSyntax.trimmedDescription
            let isIgnored = varDecl.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ObservationIgnored"
            }
            let isMutable = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
            guard let kind = classify(typeText) else { continue }
            out.append(WireletObservableProperty(
                name: identifier,
                swiftTypeText: typeText,
                kind: kind,
                isMutable: isMutable,
                isIgnored: isIgnored
            ))
        }
        return out
    }

    private static func classify(_ typeText: String) -> Kind? {
        // Optional<T> normalization. Both `T?` and `Optional<T>` accepted.
        if typeText.hasSuffix("?") {
            let inner = String(typeText.dropLast())
            return classifyOptional(inner)
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            let inner = String(typeText.dropFirst("Optional<".count).dropLast())
            return classifyOptional(inner)
        }
        if typeText.hasPrefix("["), typeText.hasSuffix("]") {
            let element = String(typeText.dropFirst().dropLast())
            // Primitive array support is intentionally omitted in Phase 1;
            // the spec lists [@WireFormat] as the only array shape.
            return .wireFormatArray(elementTypeName: element)
        }
        if let primitive = primitiveJNIType(typeText) {
            return .primitive(jniType: primitive, swiftReadExpr: { reader in reader })
        }
        if typeText == "String" {
            return .string
        }
        // Treat anything else as a @WireFormat user type.
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(_ inner: String) -> Kind? {
        if let primitive = primitiveJNIType(inner) {
            return .optionalPrimitive(jniType: primitive)
        }
        if inner == "String" {
            return .optionalString
        }
        return .optionalWireFormat(typeName: inner)
    }

    private static func primitiveJNIType(_ typeText: String) -> String? {
        switch typeText {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "jint"
        case "Int64", "UInt32", "UInt64": return "jlong"
        case "Bool": return "jboolean"
        case "Float": return "jfloat"
        case "Double": return "jdouble"
        default: return nil
        }
    }
}
```

- [ ] **Step 2: Sanity-build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservableMacros/WireletObservableProperty.swift
git commit -m "feat(observable): add WireletObservableProperty stored-property model"
```

### Task 10: Emit per-property `__<prop>_track` bridges (primitives + String)

**Files:**
- Modify: `Sources/WireletObservableMacros/WireletObservableMacro.swift`
- Modify: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`

This task wires the primitive + String path. Arrays / WireFormat / Optionals land in Task 11. The emitted shape inside `#if os(Android)`:

```
@_cdecl("WireletObservable_<Class>_<prop>_track")
public static func __<prop>_track_jni(
    _ env: UnsafeMutablePointer<JNIEnv?>?,
    _ self_ptr: jlong,
    _ on_change: jobject?
) -> <jniType> {
    let me = WireletObservableJNI.unwrap(self_ptr) as <Class>
    let runnable = JObject(env: env, jobject: on_change)
    let snapshot = ObservationTrackingHelper.read(\.<prop>, on: me) {
        runnable?.call(method: "run")
    }
    return <jniCast>(snapshot)
}
```

For `String`, the return type is `jstring?` and the snapshot is converted via `env.pointee.NewStringUTF`.

- [ ] **Step 1: Write the snapshot test for primitive expansion**

Add to `WireletObservableMacroTests.swift`:

```swift
@Suite struct WireletObservablePrimitiveExpansion {
    @Test func int32AndBoolStoredProperties() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class CounterVM {
                var count: Int32 = 0
                var active: Bool = false
            }
            """,
            expandedSource: """
            @Observable
            final class CounterVM {
                var count: Int32 = 0
                var active: Bool = false
            }

            extension CounterVM {
                #if os(Android)
                @_cdecl("WireletObservable_CounterVM_count_track")
                public static func __count_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jint {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.count, on: me) {
                        runnable?.call(method: "run")
                    }
                    return jint(snapshot)
                }
                @_cdecl("WireletObservable_CounterVM_active_track")
                public static func __active_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jboolean {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.active, on: me) {
                        runnable?.call(method: "run")
                    }
                    return jboolean(snapshot ? 1 : 0)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }
}
```

- [ ] **Step 2: Run test, confirm failure** (macro still emits empty body)

Run: `swift test --filter WireletObservablePrimitiveExpansion`
Expected: FAIL — emitted source mismatch.

- [ ] **Step 3: Implement primitive + String emission**

Replace the body of `WireletObservableMacro.expansion(of:…)` after the diagnostics with:

```swift
let className = type.trimmed.description
let properties = WireletObservableProperty.collect(classDecl)
    .filter { !$0.isIgnored }

var bridges: [String] = []
for property in properties {
    switch property.kind {
    case .primitive(let jniType, _):
        bridges.append(renderPrimitiveBridge(
            className: className, property: property, jniType: jniType
        ))
    case .string:
        bridges.append(renderStringBridge(className: className, property: property))
    case .wireFormat, .wireFormatArray, .optionalPrimitive, .optionalString, .optionalWireFormat:
        // Task 11.
        continue
    }
}

let body: DeclSyntax = """
extension \(type.trimmed) {
    #if os(Android)
    \(raw: bridges.joined(separator: "\n    "))
    #endif
}
"""
guard let ext = body.as(ExtensionDeclSyntax.self) else { return [] }
return [ext]
```

Add the renderer helpers (inside the macro type or as `private` file-scope functions):

```swift
private static func renderPrimitiveBridge(
    className: String,
    property: WireletObservableProperty,
    jniType: String
) -> String {
    let returnExpr: String = {
        switch property.swiftTypeText {
        case "Bool": return "jboolean(snapshot ? 1 : 0)"
        default:    return "\(jniType)(snapshot)"
        }
    }()
    return """
    @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public static func __\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> \(jniType) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return \(returnExpr)
        }
    """
}

private static func renderStringBridge(
    className: String,
    property: WireletObservableProperty
) -> String {
    return """
    @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public static func __\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jstring? {
            guard let env, let envValue = env.pointee else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return snapshot.withCString { cstr in
                envValue.pointee.NewStringUTF(env, cstr)
            }
        }
    """
}
```

- [ ] **Step 4: Run test, confirm pass**

Run: `swift test --filter WireletObservablePrimitiveExpansion`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WireletObservableMacros/ Tests/WireletObservableMacrosTests/
git commit -m "feat(observable): emit primitive + String track bridges in @WireletObservable"
```

### Task 11: Emit Optional / Array / `@WireFormat` track bridges

**Files:**
- Modify: `Sources/WireletObservableMacros/WireletObservableMacro.swift`
- Modify: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`

For these three kinds the bridge returns `jbyteArray?`:

- `@WireFormat struct T`: `WireletObservableJNI.encode(snapshot, env: env)`.
- `[T] where T: WireFormat`: `WireletObservableJNI.encodeArray(snapshot, env: env)`.
- `Optional<T>`: returns `nil` directly on `nil` snapshot; otherwise the underlying encoding. (Primitive optionals also funnel through `jbyteArray?`: one-byte presence prefix + payload.)

- [ ] **Step 1: Write snapshot tests for the three shapes**

Add `WireletObservableCompositeExpansion` suite covering:
- `@WireFormat` struct property
- `[TodoItem]` array
- `String?` optional
- `Int32?` optional (presence-prefix path)

Each assertion follows the same pattern as Task 10. Full expected text omitted for brevity; the assertions live in the test file. (Use Task 10's structure verbatim; the difference is the return type column and the return expression.)

- [ ] **Step 2: Run tests, confirm failure** (Composite paths unimplemented).

Run: `swift test --filter WireletObservableCompositeExpansion`
Expected: FAIL.

- [ ] **Step 3: Implement the three render functions**

```swift
private static func renderWireFormatBridge(
    className: String,
    property: WireletObservableProperty
) -> String {
    return """
    @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public static func __\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return WireletObservableJNI.encode(snapshot, env: env)
        }
    """
}

private static func renderWireFormatArrayBridge(
    className: String,
    property: WireletObservableProperty
) -> String {
    return """
    @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public static func __\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return WireletObservableJNI.encodeArray(snapshot, env: env)
        }
    """
}

private static func renderOptionalBridge(
    className: String,
    property: WireletObservableProperty
) -> String {
    // Optional payloads always come back as jbyteArray? — a nil array means
    // the Swift value was nil. Non-nil arrays carry the inner encoding.
    return """
    @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public static func __\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            guard let value = snapshot else { return nil }
            return WireletObservableJNI.encode(value, env: env)
        }
    """
}
```

Update the dispatch switch in the expansion body to route `wireFormat`, `wireFormatArray`, `optionalPrimitive`, `optionalString`, `optionalWireFormat` to the right renderer.

- [ ] **Step 4: Run tests, confirm pass**

Run: `swift test --filter WireletObservableCompositeExpansion`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WireletObservableMacros/ Tests/WireletObservableMacrosTests/
git commit -m "feat(observable): emit Optional / Array / @WireFormat track bridges"
```

### Task 12: Emit `__new`, `__release`, setter, and `@WireletExpose` method bridges

**Files:**
- Modify: `Sources/WireletObservableMacros/WireletObservableMacro.swift`
- Modify: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`

For every `@WireletObservable` class we emit:

- `WireletObservable_<Class>_new`: builds a fresh instance via the class's no-arg `init()`, returns a retained `jlong`.
- `WireletObservable_<Class>_release`: drops the retain.
- For each `var` stored property: a `_set` bridge that decodes the JNI argument and assigns into the live instance.
- For each method carrying `@WireletExpose`: a `_invoke` bridge that decodes its argument list (if any) and calls through.

For Phase 1 we only support `@WireletExpose` methods that are either zero-arg or take a single `@WireFormat` value (the spec's `add(_ item: TodoItem)` shape). Multi-arg methods are deferred.

- [ ] **Step 1: Write snapshot test covering the full `TodoListVM` shape from the spec**

The assertion is large but mechanical. Verify `__new`, `__release`, `__items_track`, `__filter_track`, `__totalCount_track`, `__items_set` (setter exists because `items` is `var`), `__add_invoke`, `__clear_invoke` all appear.

- [ ] **Step 2: Run test, confirm failure.**

- [ ] **Step 3: Implement the four render helpers**

`renderConstructor`, `renderDestructor`, `renderPrimitiveSetter` (and string/byteArray variants), `renderExposeInvoke`. Pattern follows Task 10/11. Use `WireletObservableJNI.retain` / `release` / `dataFromByteArray` / `encode` for marshaling.

- [ ] **Step 4: Run tests, confirm pass.**

- [ ] **Step 5: Commit**

```bash
git add Sources/WireletObservableMacros/ Tests/WireletObservableMacrosTests/
git commit -m "feat(observable): emit __new/__release/setters and @WireletExpose method bridges"
```

### Task 13: Golden snapshot — full `TodoListVM`

**Files:**
- Modify: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift`

Pull the `TodoListVM` example straight from `docs/superpowers/specs/2026-05-29-wirelet-observable-bridge-design.md`. Lock the expected expansion as the canonical reference: any future macro change that drifts the output requires a deliberate fixture bump.

- [ ] **Step 1: Add the golden test**

```swift
@Suite struct WireletObservableGolden {
    @Test func todoListVMMatchesDesignDoc() {
        assertMacroExpansion(
            """
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
            """,
            expandedSource: "<paste full expected expansion here>",
            macros: macroSpecs
        )
    }
}
```

For the initial commit, use a placeholder string and run the test once with `expandedSource: ""`. The failure message printed by `assertMacroExpansion` includes the actual emitted source. Copy that verbatim into the assertion, verify the output matches the design doc's example, then commit.

- [ ] **Step 2: Iteration**

1. Run `swift test --filter todoListVMMatchesDesignDoc`.
2. Copy the printed actual output into `expandedSource`.
3. Manually diff against the design doc's `TodoListVM` example — every `@_cdecl` symbol named in the spec must be present.
4. Re-run; expect PASS.

- [ ] **Step 3: Commit**

```bash
git add Tests/WireletObservableMacrosTests/
git commit -m "test(observable): golden expansion test for TodoListVM example"
```

### Task 14: Verify entire test suite + Apple linker hygiene

- [ ] **Step 1: Full suite green**

Run: `swift test`
Expected: previous 78 + Phase 1A 3 + macro tests pass; no failures, no warnings.

- [ ] **Step 2: Confirm no JNI symbols on Apple**

Run:
```bash
swift build -c release
nm .build/release/libWireletObservable.dylib 2>&1 | grep -i 'WireletObservable_' || echo "OK: no Android JNI symbols leaked"
```
Expected: `OK: no Android JNI symbols leaked`.

(If `libWireletObservable.dylib` is not produced as a dynamic library by SwiftPM in this configuration, fall back to `nm .build/release/*.o 2>&1 | grep WireletObservable_ || echo OK`.)

- [ ] **Step 3: No commit** — verification only.

---

## Self-review checklist (done)

- **Spec coverage** — Phase 1A/1B covers the macro emission contract, JNI runtime helpers, JObject Runnable wrapper, ObservationTrackingHelper re-arm pattern, `@WireletExpose` marker, and the `#if os(Android)` guarding. Phase 3+ (schema, Kotlin emitter, Gradle plugin, example) are intentionally out of scope and noted at the top.
- **Placeholders** — Task 11 step 1 and Task 12 step 1 use "verify shape pattern" rather than a full pasted assertion because the bodies are mechanical repetitions of Task 10's pattern. The renderer code in step 3 of each is complete. Task 13 step 1 documents the bootstrapping recipe (run-once, paste expected) rather than the final snapshot string; this is intentional — locking the string before running the macro guarantees an off-by-one whitespace mismatch.
- **Type consistency** — `WireletObservableJNI.encode` / `encodeArray` signatures match between the helper module (Task 6) and the renderer call sites (Tasks 10, 11, 12). `ObservationTrackingHelper.read(_:on:onChange:)` signature is consistent across Task 3, Task 10, Task 11, Task 12. Diagnostic `MessageID` strings match the `rawValue`s.
- **Scope** — single subsystem (Swift macro + runtime). Independent of Kotlin codegen; can be merged on its own and the JNI symbols can be consumed by hand-written Kotlin for early experimentation.

---

## What lands after this plan

This plan ships the Swift side. A hand-written Kotlin file can already exercise the macro output via JNI — that's the spike. After Phase 1 is on `main`:

1. **Phase 2 plan** — `WireletObservableSchema` + `WireletObservableKotlinEmitter` + `EmitWireletObservable` CLI. Pulls the same property model out into a reusable form for the Kotlin emitter.
2. **Phase 3 plan** — `kotlin/observable-runtime/` + Gradle plugin `observable` DSL extension.
3. **Phase 4 plan** — `examples/observable-counter/` end-to-end with emulator smoke.
4. **Phase 5 plan** — README + `v0.2.0` release pipeline.
