# Wirelet Provided bridge — Phase 1 (schema + macro) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `@WireletProvided` marker macro and a `WireletProvidedSchema` module that parses `@WireletProvided` Swift protocols into an in-memory schema, so the Phase 2/3 emitters have a structured model to render from.

**Architecture:** Mirror the existing `@WireletObservable` machinery. `@WireletProvided` is a diagnostic-only `PeerMacro` (validates it sits on a protocol, emits no Swift code) — the real Swift proxy / Kotlin interface are generated offline by later-phase CLIs, exactly as the observable bridges are. `WireletProvidedSchema` is a pure structural model + a `SwiftSyntax` visitor that finds `@WireletProvided` protocols and records their methods (name, parameters, return type as source text). Both are fully host-testable on macOS — no Android, no JNI.

**Tech Stack:** Swift 6 macros (`SwiftSyntax`, `SwiftSyntaxMacros`, `SwiftCompilerPlugin`, `SwiftDiagnostics`), `SwiftParser` for the schema visitor, Swift Testing for schema tests, XCTest + `SwiftSyntaxMacrosTestSupport` for macro tests (matching the existing `WireletObservableMacrosTests` harness).

**Scope note:** Phase 1 is JUST the provided-protocol schema + marker macro. Type *classification* (mapping params/returns to JNI kinds) is deferred to the Phase 2/3 emitters, which reuse the existing public `InvokeArgClassifier` (`Sources/WireletObservableSchema/Internal/InvokeArgClassifier.swift`) — the schema model stores parameter/return types as source text only, mirroring how `ObservableMethodParameter` stores `typeText` (not a classified kind). The spec's "classify `@WireletObservable`-init service params" item is also deferred to Phase 2 (it modifies the *observable* schema and is only consumed by the injection codegen). This keeps Phase 1 dependency-light (only swift-syntax) and a clean TDD unit.

**Reference equivalents to mirror (read before starting):**
- Macro decl: `Sources/WireletObservable/WireletObservable.swift`
- Macro impl: `Sources/WireletObservableMacros/WireletObservableMacro.swift`, `WireletObservableDiagnostic.swift`, `Plugin.swift`
- Schema model: `Sources/WireletObservableSchema/ObservableSchema.swift`
- Schema parser: `Sources/WireletObservableSchema/ObservableSchemaParser.swift`
- Schema tests: `Tests/WireletObservableSchemaTests/ObservableSchemaParserTests.swift` (Swift Testing + `Bundle.module` fixtures)
- Macro tests: `Tests/WireletObservableMacrosTests/WireletObservableMacroTests.swift` (XCTest + `assertMacroExpansion`)
- Package wiring: `Package.swift`

All paths below are under `/Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`. Branch `provided-bridge`. Use `git -C`, absolute paths, one Bash command per call (no `&&`/`;`/`cd …`).

---

## File Structure

**Created — schema (Task 1):**
- `Sources/WireletProvidedSchema/ProvidedSchema.swift` — the value-type model (`ProvidedSchema`, `ProvidedService`, `ProvidedMethod`, `ProvidedParameter`).
- `Sources/WireletProvidedSchema/ProvidedSchemaParser.swift` — `parse(source:fileName:)` + the `ProtocolDeclSyntax` visitor.
- `Tests/WireletProvidedSchemaTests/ProvidedSchemaParserTests.swift` — Swift Testing parser tests.
- `Tests/WireletProvidedSchemaTests/Fixtures/TodoStoreService.swift` — a fixture protocol (resource, not compiled).
- `Tests/WireletProvidedSchemaTests/Fixtures/MixedDecls.swift` — a fixture with no `@WireletProvided` protocol.

**Created — macro (Task 2):**
- `Sources/WireletProvided/WireletProvided.swift` — the public `@WireletProvided` macro declaration (marker library).
- `Sources/WireletProvidedMacros/WireletProvidedMacro.swift` — the diagnostic-only `PeerMacro`.
- `Sources/WireletProvidedMacros/WireletProvidedDiagnostic.swift` — diagnostic messages.
- `Sources/WireletProvidedMacros/Plugin.swift` — compiler-plugin registration.
- `Tests/WireletProvidedMacrosTests/WireletProvidedMacroTests.swift` — XCTest macro-expansion tests.

**Modified (both tasks):**
- `Package.swift` — new targets, one product, two test targets.

---

## Task 1: `WireletProvidedSchema` — model + parser + host tests

**Files:**
- Create: `Sources/WireletProvidedSchema/ProvidedSchema.swift`
- Create: `Sources/WireletProvidedSchema/ProvidedSchemaParser.swift`
- Create: `Tests/WireletProvidedSchemaTests/Fixtures/TodoStoreService.swift`
- Create: `Tests/WireletProvidedSchemaTests/Fixtures/MixedDecls.swift`
- Create: `Tests/WireletProvidedSchemaTests/ProvidedSchemaParserTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write the schema model**

Create `Sources/WireletProvidedSchema/ProvidedSchema.swift`:

```swift
import Foundation

/// In-memory description of every `@WireletProvided` protocol discovered
/// across a set of Swift source files. Mirrors `ObservableSchema` for the
/// observable triad; here each entry is a Kotlin-implemented service the
/// Swift side calls.
public struct ProvidedSchema: Equatable, Sendable {
    public var services: [ProvidedService]
    public init(services: [ProvidedService]) {
        self.services = services
    }
}

/// One discovered `@WireletProvided protocol`.
public struct ProvidedService: Equatable, Sendable {
    /// Protocol name as written in source. The emitters apply naming
    /// transforms (proxy suffix on Swift, adapter suffix on Kotlin).
    public var name: String
    /// All protocol methods in declaration order. Unlike the observable
    /// model there is no per-method marker — the protocol attribute marks
    /// the whole surface.
    public var methods: [ProvidedMethod]
    public init(name: String, methods: [ProvidedMethod]) {
        self.name = name
        self.methods = methods
    }
}

public struct ProvidedMethod: Equatable, Sendable {
    public var name: String
    /// Parameter list as written in source. Per-parameter types are
    /// classified later (Phase 2/3 emitters reuse `InvokeArgClassifier`);
    /// the schema stays a pure structural record.
    public var parameters: [ProvidedParameter]
    /// The return type as written in source (e.g. `[TodoItem]`, `Int32`),
    /// or `nil` when the method has no return clause (a `Void` method).
    public var returnTypeText: String?
    public init(
        name: String,
        parameters: [ProvidedParameter],
        returnTypeText: String?
    ) {
        self.name = name
        self.parameters = parameters
        self.returnTypeText = returnTypeText
    }
}

public struct ProvidedParameter: Equatable, Sendable {
    /// First (external) label as written in source. `_` is preserved so the
    /// emitter can decide whether to drop the label at the Swift call site.
    public var label: String
    /// Second (internal) name, or `nil` when the parameter has a single name.
    public var internalName: String?
    /// Swift type text as written in source (e.g. `TodoItem`, `Int32`).
    public var typeText: String
    public init(label: String, internalName: String? = nil, typeText: String) {
        self.label = label
        self.internalName = internalName
        self.typeText = typeText
    }
}
```

- [ ] **Step 2: Write the two test fixtures**

Create `Tests/WireletProvidedSchemaTests/Fixtures/TodoStoreService.swift` (a resource — never compiled, only parsed as text):

```swift
import Wirelet
import WireletProvided

@WireFormat
struct TodoItem: Equatable, Sendable {
    var id: Int32
    var title: String
    var done: Bool
}

@WireletProvided
protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}
```

Create `Tests/WireletProvidedSchemaTests/Fixtures/MixedDecls.swift`:

```swift
// A plain protocol without @WireletProvided — must be ignored.
protocol PlainProtocol {
    func foo()
}

// @WireletProvided on a non-protocol — the parser only visits protocols,
// so this contributes nothing (the macro layer diagnoses it separately).
@WireletProvided
struct NotAProtocol {}

final class SomeClass {}
```

- [ ] **Step 3: Write the failing parser tests**

Create `Tests/WireletProvidedSchemaTests/ProvidedSchemaParserTests.swift`:

```swift
import Foundation
import Testing
@testable import WireletProvidedSchema

@Test func parsesTodoStoreService() throws {
    let url = try #require(Bundle.module.url(
        forResource: "TodoStoreService",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ProvidedSchemaParser.parse(source: source, fileName: "TodoStoreService.swift")

    #expect(schema.services.count == 1)
    let service = schema.services[0]
    #expect(service.name == "TodoStore")
    #expect(service.methods == [
        ProvidedMethod(name: "loadAll", parameters: [], returnTypeText: "[TodoItem]"),
        ProvidedMethod(
            name: "add",
            parameters: [ProvidedParameter(label: "_", internalName: "item", typeText: "TodoItem")],
            returnTypeText: nil
        ),
        ProvidedMethod(
            name: "remove",
            parameters: [ProvidedParameter(label: "_", internalName: "id", typeText: "Int32")],
            returnTypeText: nil
        ),
    ])
}

@Test func ignoresNonProvidedDecls() throws {
    let url = try #require(Bundle.module.url(
        forResource: "MixedDecls",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ProvidedSchemaParser.parse(source: source, fileName: "MixedDecls.swift")

    #expect(schema.services.isEmpty)
}
```

- [ ] **Step 4: Write a stub parser (so the package builds, tests fail on assertions)**

Create `Sources/WireletProvidedSchema/ProvidedSchemaParser.swift` with a stub that returns an empty schema:

```swift
import Foundation
import SwiftParser
import SwiftSyntax

public enum ProvidedSchemaParser {
    public static func parse(source: String, fileName: String) -> ProvidedSchema {
        return ProvidedSchema(services: [])
    }
}
```

- [ ] **Step 5: Wire the new targets into `Package.swift`**

In `Package.swift`, add the schema target immediately after the existing `WireletObservableSchema` target. Find this exact block:

```swift
        .target(
            name: "WireletObservableSchema",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
```

and insert directly after it:

```swift
        .target(
            name: "WireletProvidedSchema",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
```

Then add the test target immediately after the existing `WireletObservableSchemaTests` test target. Find this exact block:

```swift
        .testTarget(
            name: "WireletObservableSchemaTests",
            dependencies: ["WireletObservableSchema"],
            resources: [.copy("Fixtures")]
        ),
```

and insert directly after it:

```swift
        .testTarget(
            name: "WireletProvidedSchemaTests",
            dependencies: ["WireletProvidedSchema"],
            resources: [.copy("Fixtures")]
        ),
```

- [ ] **Step 6: Run the tests to verify they FAIL on assertions (not compile errors)**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedSchemaTests`
Expected: builds successfully; `parsesTodoStoreService` FAILS (`schema.services.count == 1` is `0 == 1`). `ignoresNonProvidedDecls` passes (stub returns empty). If you get a *compile* error instead of a test failure, fix it before continuing — the test should fail on the assertion.

- [ ] **Step 7: Implement the real parser**

Replace `Sources/WireletProvidedSchema/ProvidedSchemaParser.swift` with:

```swift
import Foundation
import SwiftParser
import SwiftSyntax

public enum ProvidedSchemaParser {
    /// Parses the `@WireletProvided` protocols declared in a Swift source
    /// file. Declarations that are not protocols, or protocols lacking the
    /// attribute, are silently skipped.
    public static func parse(source: String, fileName: String) -> ProvidedSchema {
        let tree = Parser.parse(source: source)
        let visitor = ProvidedVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return ProvidedSchema(services: visitor.services)
    }
}

final class ProvidedVisitor: SyntaxVisitor {
    var services: [ProvidedService] = []

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasAttribute(node.attributes, named: "WireletProvided") else {
            return .visitChildren
        }
        let methods = collectMethods(of: node)
        services.append(ProvidedService(name: node.name.text, methods: methods))
        return .visitChildren
    }

    private func collectMethods(of proto: ProtocolDeclSyntax) -> [ProvidedMethod] {
        var out: [ProvidedMethod] = []
        for member in proto.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            let params = funcDecl.signature.parameterClause.parameters.map { param in
                ProvidedParameter(
                    label: param.firstName.text,
                    internalName: param.secondName?.text,
                    typeText: param.type.trimmedDescription
                )
            }
            let returnTypeText = funcDecl.signature.returnClause?.type.trimmedDescription
            out.append(ProvidedMethod(
                name: funcDecl.name.text,
                parameters: params,
                returnTypeText: returnTypeText
            ))
        }
        return out
    }

    private func hasAttribute(_ list: AttributeListSyntax, named name: String) -> Bool {
        for element in list {
            guard let attr = element.as(AttributeSyntax.self) else { continue }
            if attr.attributeName.trimmedDescription == name { return true }
        }
        return false
    }
}
```

- [ ] **Step 8: Run the tests to verify they PASS**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedSchemaTests`
Expected: both tests pass.

- [ ] **Step 9: Commit**

```
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet add Sources/WireletProvidedSchema Tests/WireletProvidedSchemaTests Package.swift
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet commit -m "feat(provided): WireletProvidedSchema model + parser for @WireletProvided protocols"
```

---

## Task 2: `@WireletProvided` marker macro + diagnostics + host tests

**Files:**
- Create: `Sources/WireletProvided/WireletProvided.swift`
- Create: `Sources/WireletProvidedMacros/WireletProvidedMacro.swift`
- Create: `Sources/WireletProvidedMacros/WireletProvidedDiagnostic.swift`
- Create: `Sources/WireletProvidedMacros/Plugin.swift`
- Create: `Tests/WireletProvidedMacrosTests/WireletProvidedMacroTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write the diagnostic messages**

Create `Sources/WireletProvidedMacros/WireletProvidedDiagnostic.swift`:

```swift
import SwiftDiagnostics

enum WireletProvidedDiagnostic: String, DiagnosticMessage {
    case notAProtocol

    var diagnosticID: MessageID {
        MessageID(domain: "WireletProvided", id: rawValue)
    }
    var severity: DiagnosticSeverity { .error }
    var message: String {
        switch self {
        case .notAProtocol:
            return "@WireletProvided can only be applied to a protocol."
        }
    }
}
```

- [ ] **Step 2: Write the diagnostic-only peer macro**

Create `Sources/WireletProvidedMacros/WireletProvidedMacro.swift`:

```swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Diagnostic-only peer macro. Validates that `@WireletProvided` is applied
/// to a protocol. No Swift code is emitted — the Swift proxy and Kotlin
/// interface/adapter are generated offline by the Phase 2/3 CLIs, exactly
/// as the `@WireletObservable` JNI bridges are.
public struct WireletProvidedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireletProvidedDiagnostic.notAProtocol
            ))
            return []
        }
        return []
    }
}
```

- [ ] **Step 3: Write the compiler-plugin registration**

Create `Sources/WireletProvidedMacros/Plugin.swift`:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletProvidedPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireletProvidedMacro.self,
    ]
}
```

- [ ] **Step 4: Write the public macro declaration (marker library)**

Create `Sources/WireletProvided/WireletProvided.swift`:

```swift
/// Marker attribute for a `protocol` whose implementation is supplied on
/// the Kotlin side and called from Swift over JNI. The macro emits no Swift
/// code; the `EmitWireletProvided*` CLIs (Phase 2/3) scan for this attribute
/// and generate the Swift proxy + Kotlin interface/adapter.
///
/// On Apple platforms the attribute is inert: a `@WireletProvided protocol`
/// is an ordinary protocol, so a Swift conformance can be injected directly
/// for host unit tests.
///
/// Restrictions:
/// - Must be applied to a `protocol`.
/// - Method parameters and return types must be a primitive
///   (`Int8/16/32/64`, `UInt8/16/32/64`, `Bool`, `Float`, `Double`),
///   `String`, a `@WireFormat` struct/enum, or `Array` / `Optional`
///   thereof. (Enforced by the Phase 2/3 emitters via `InvokeArgClassifier`,
///   not by this marker.)
@attached(peer)
public macro WireletProvided() = #externalMacro(
    module: "WireletProvidedMacros",
    type: "WireletProvidedMacro"
)
```

- [ ] **Step 5: Wire the new targets + product into `Package.swift`**

(a) Add the macro target. Find the existing `WireletObservableMacros` macro target block:

```swift
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

and insert directly after it:

```swift
        .macro(
            name: "WireletProvidedMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "WireletProvided",
            dependencies: [
                "WireletProvidedMacros",
            ]
        ),
```

(b) Add the library product. Find this product line:

```swift
        .library(name: "WireletObservable", targets: ["WireletObservable"]),
```

and insert directly after it:

```swift
        .library(name: "WireletProvided", targets: ["WireletProvided"]),
```

(c) Add the macro test target. Find the existing `WireletObservableMacrosTests` test target block:

```swift
        .testTarget(
            name: "WireletObservableMacrosTests",
            dependencies: [
                "WireletObservableMacros",
                "WireletObservable",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
```

and insert directly after it:

```swift
        .testTarget(
            name: "WireletProvidedMacrosTests",
            dependencies: [
                "WireletProvidedMacros",
                "WireletProvided",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
```

- [ ] **Step 6: Write the macro-expansion tests (XCTest, mirroring the observable harness)**

Create `Tests/WireletProvidedMacrosTests/WireletProvidedMacroTests.swift`:

```swift
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletProvidedMacros

private let macroSpecs: [String: any Macro.Type] = [
    "WireletProvided": WireletProvidedMacro.self,
]

final class WireletProvidedMacroTests: XCTestCase {
    func testProtocolExpandsToItselfWithNoPeers() {
        assertMacroExpansion(
            """
            @WireletProvided
            protocol TodoStore {
                func loadAll() -> [TodoItem]
                func add(_ item: TodoItem)
            }
            """,
            expandedSource: """
            protocol TodoStore {
                func loadAll() -> [TodoItem]
                func add(_ item: TodoItem)
            }
            """,
            macros: macroSpecs
        )
    }

    func testNonProtocolEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletProvided
            struct NotAProtocol {
            }
            """,
            expandedSource: """
            struct NotAProtocol {
            }
            """,
            diagnostics: [
                .init(message: "@WireletProvided can only be applied to a protocol.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }
}
```

- [ ] **Step 7: Run the macro tests to verify they PASS**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet --filter WireletProvidedMacrosTests`
Expected: both tests pass. (If the diagnostic line/column differs, adjust the `DiagnosticSpec` to match — the attribute is on line 1; `assertMacroExpansion` reports the diagnostic at the attribute node.)

- [ ] **Step 8: Run the FULL package test suite to confirm no regression**

Run: `swift test --package-path /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet`
Expected: the whole suite passes (the existing ~115 tests plus the new schema + macro tests). Confirm no existing test broke from the `Package.swift` additions.

- [ ] **Step 9: Commit**

```
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet add Sources/WireletProvided Sources/WireletProvidedMacros Tests/WireletProvidedMacrosTests Package.swift
git -C /Users/kiichi/Developer/Personal/swift-packages/swift-wirelet commit -m "feat(provided): @WireletProvided marker macro (diagnostic-only) + tests"
```

---

## Self-Review

- **Spec coverage (Phase 1 slice):** The spec's Phase 1 = "Schema — parse `@WireletProvided` protocols; classify method params/returns; classify observable-init service params." Tasks 1–2 deliver the parse + the marker macro. Classification is intentionally deferred to the Phase 2/3 emitters (which reuse the existing public `InvokeArgClassifier`) so the schema stays a pure structural model — exactly mirroring how `ObservableMethodParameter` stores only `typeText`. The observable-init service-param classification is deferred to Phase 2 (it edits the *observable* schema and is only used by the injection codegen); this is called out in the Scope note so it is not silently dropped.
- **Placeholder scan:** No "TBD"/"add validation"/"similar to". Every step has complete file contents or exact `Package.swift` insertion anchors. The one adaptive note (Step 7 diagnostic line/column) points at a concrete value to confirm via the real test run, not unwritten work.
- **Type consistency:** `ProvidedSchema`/`ProvidedService`/`ProvidedMethod`/`ProvidedParameter` field names and initializers used in the Task 1 tests (`ProvidedMethod(name:parameters:returnTypeText:)`, `ProvidedParameter(label:internalName:typeText:)`) exactly match the model defined in Step 1. The parser (`ProvidedSchemaParser.parse(source:fileName:)`) matches the test call sites. The macro decl points `module: "WireletProvidedMacros", type: "WireletProvidedMacro"` matching the impl + plugin registration. `Package.swift` target names (`WireletProvidedSchema`, `WireletProvided`, `WireletProvidedMacros`, `WireletProvidedSchemaTests`, `WireletProvidedMacrosTests`) are consistent across both tasks and the test-target dependency lists.
- **Build ordering:** Each task adds its `Package.swift` entries together with its sources and tests, so the package always resolves; the schema task is independent of the macro task (the parser matches the attribute by source text, not by the macro existing), and either could build alone.
