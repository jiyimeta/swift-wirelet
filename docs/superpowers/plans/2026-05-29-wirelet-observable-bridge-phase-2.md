# Wirelet Observable Bridge — Phase 2: Schema parser + Kotlin emitter + CLI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the host-side codegen toolchain for `@WireletObservable` view-models: a Swift-source parser (`WireletObservableSchema`), a Kotlin file emitter (`WireletObservableKotlinEmitter`) that produces `<Name>ViewModel.kt` per the spec's "Kotlin codegen contract", and an `emit-wirelet-observable` CLI that drives them end-to-end from a config + source-tree + output-dir. Kotlin runtime (`wirelet-observable-runtime`), the Gradle plugin DSL, and the Android example land in later phases.

**Architecture:** Mirror the existing `WireletSchema` / `WireletKotlinEmitter` / `EmitWireletKotlin` triad. `WireletObservableSchema` walks `.swift` files with `SwiftParser` and collects every `class` that carries both `@WireletObservable` and `@Observable`, recording its stored properties (skipping `@ObservationIgnored` and static) and `@WireletExpose` methods. `WireletObservableKotlinEmitter` consumes that schema plus a JSON-decodable `ObservableCodegenConfig` and produces one `KotlinFile` per view-model containing the `MutableStateFlow` wrappers, re-arm helpers, `external fun` declarations, and the companion `loadLibrary` + `nativeNew` block. `EmitWireletObservable` is a SwiftPM executable that wires source enumeration, config load, file write, and stale-file sweep — same shape as `EmitWireletKotlin`.

**Tech Stack:** Swift 6.0, SwiftPM, SwiftSyntax 603 / SwiftParser, Swift Testing for unit tests, JSONDecoder for config, Foundation for filesystem.

---

## File Structure

**Create:**
- `Sources/WireletObservableSchema/ObservableSchema.swift` — model: `ObservableSchema`, `ObservableViewModel`, `ObservableProperty`, `ObservableMethod`, `ObservablePropertyKind`.
- `Sources/WireletObservableSchema/ObservableSchemaParser.swift` — `SwiftParser`-based visitor; entry point `ObservableSchemaParser.parse(source:fileName:)`.
- `Sources/WireletObservableSchema/Internal/ObservableTypeClassifier.swift` — Swift-type-text → `ObservablePropertyKind` mapping; mirrors the macro's classify rules but in a schema-friendly shape (no closures).
- `Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift` — JSON-decodable config: view-model package, model package, codec package, runtime package, library name, name transform.
- `Sources/WireletObservableKotlinEmitter/ObservableKotlinEmitter.swift` — emit entry: schema in, `[KotlinFile]` out. Reuses `KotlinFile` from `WireletKotlinEmitter`.
- `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift` — `ObservablePropertyKind` + Swift-type-text → Kotlin type + JNI return type + tracker render strategy.
- `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift` — renders one `<Name>ViewModel.kt`.
- `Sources/EmitWireletObservable/main.swift` — CLI: argv parse, source enumeration, emitter invocation, idempotent file write + stale-file sweep.
- `Tests/WireletObservableSchemaTests/ObservableSchemaParserTests.swift` — parser tests.
- `Tests/WireletObservableSchemaTests/Fixtures/CounterVM.swift` — primitive-only VM fixture.
- `Tests/WireletObservableSchemaTests/Fixtures/TodoListVM.swift` — full VM fixture (array, string, exposed methods, ignored property).
- `Tests/WireletObservableSchemaTests/Fixtures/MixedDecls.swift` — fixture mixing `@WireletObservable` class, plain `@Observable` class, plain `@WireFormat` struct, plain class.
- `Tests/WireletObservableKotlinEmitterTests/CounterViewModelEmitterTests.swift` — golden test for primitive-only VM.
- `Tests/WireletObservableKotlinEmitterTests/TodoListViewModelEmitterTests.swift` — golden test for full VM.
- `Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt` — golden file.
- `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt` — golden file.
- `Tests/EmitWireletObservableTests/CLISmokeTests.swift` — end-to-end CLI test.
- `Tests/EmitWireletObservableTests/Fixtures/observable-codegen.json` — CLI config fixture.
- `Tests/EmitWireletObservableTests/Fixtures/sources/TodoListVM.swift` — CLI source fixture.
- `Tests/EmitWireletObservableTests/Fixtures/sources/TodoItem.swift` — companion `@WireFormat` fixture (parsed-only, never compiled — present so the source tree resembles a real consumer's project).

**Modify:**
- `Package.swift` — add three new library/executable targets + three new test targets; add `emit-wirelet-observable` to products.

**Out of scope (future plans):**
- `kotlin/observable-runtime/` Gradle module — Phase 3 plan.
- `kotlin/gradle-plugin/observable` DSL extension — Phase 3 plan.
- `examples/observable-counter/` Android example + emulator CI — Phase 4 plan.
- README "Observable bridge" section + `v0.2.0` publish — Phase 5 plan.

---

## Phase 2A: Schema parser

### Task 1: Register new targets in `Package.swift`

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add executable to `products`**

Find the line:

```swift
.executable(name: "emit-wirelet-kotlin", targets: ["EmitWireletKotlin"]),
```

Insert immediately after:

```swift
.executable(name: "emit-wirelet-observable", targets: ["EmitWireletObservable"]),
```

- [ ] **Step 2: Add three library/executable targets to `targets`**

Find the existing `EmitWireletKotlin` executableTarget entry. Insert the three new targets immediately after it:

```swift
.target(
    name: "WireletObservableSchema",
    dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
    ]
),
.target(
    name: "WireletObservableKotlinEmitter",
    dependencies: [
        "WireletObservableSchema",
        "WireletKotlinEmitter",
    ]
),
.executableTarget(
    name: "EmitWireletObservable",
    dependencies: [
        "WireletObservableSchema",
        "WireletObservableKotlinEmitter",
    ]
),
```

`WireletObservableKotlinEmitter` depends on `WireletKotlinEmitter` so it can reuse the public `KotlinFile` struct (Sources/WireletKotlinEmitter/KotlinEmitter.swift:3–10). No need to lift `KotlinFile` into a third target.

- [ ] **Step 3: Add three test targets to `targets`**

Append after the existing `.testTarget(name: "WireletObservableMacrosTests", …)` block:

```swift
.testTarget(
    name: "WireletObservableSchemaTests",
    dependencies: ["WireletObservableSchema"],
    resources: [.copy("Fixtures")]
),
.testTarget(
    name: "WireletObservableKotlinEmitterTests",
    dependencies: [
        "WireletObservableKotlinEmitter",
        "WireletObservableSchema",
    ],
    resources: [.copy("Fixtures")]
),
.testTarget(
    name: "EmitWireletObservableTests",
    dependencies: [
        "EmitWireletObservable",
        "WireletObservableKotlinEmitter",
        "WireletObservableSchema",
    ],
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 4: Verify the package still resolves**

Run: `swift build --target WireletObservable`
Expected: builds without error (the new targets have no sources yet, but SwiftPM still resolves the graph). If the new targets cause an "unknown source files" warning that's fine — they get sources in subsequent tasks.

- [ ] **Step 5: Commit**

```bash
git add Package.swift
git commit -m "build(observable): register Phase 2 schema/emitter/CLI targets"
```

### Task 2: `WireletObservableSchema` model types

**Files:**
- Create: `Sources/WireletObservableSchema/ObservableSchema.swift`

- [ ] **Step 1: Write `ObservableSchema.swift`**

```swift
import Foundation

/// In-memory description of every `@WireletObservable @Observable` class
/// discovered across a set of Swift source files. Mirrors the role of
/// `WireletSchema.Schema` for the wireformat triad.
public struct ObservableSchema: Equatable, Sendable {
    public var viewModels: [ObservableViewModel]
    public init(viewModels: [ObservableViewModel]) {
        self.viewModels = viewModels
    }
}

/// One discovered `@WireletObservable @Observable final class`.
public struct ObservableViewModel: Equatable, Sendable {
    /// Swift class name as it appears in source. The Kotlin emitter applies
    /// the configured `NameTransform` plus the `ViewModel` suffix.
    public var name: String
    /// Stored properties in declaration order. `@ObservationIgnored`
    /// properties and `static`/`class` properties are filtered out by the
    /// parser before this list is constructed.
    public var properties: [ObservableProperty]
    /// `@WireletExpose`-annotated methods in declaration order. Plain
    /// methods are excluded.
    public var methods: [ObservableMethod]
    public init(
        name: String,
        properties: [ObservableProperty],
        methods: [ObservableMethod]
    ) {
        self.name = name
        self.properties = properties
        self.methods = methods
    }
}

public struct ObservableProperty: Equatable, Sendable {
    public var name: String
    /// The Swift type as written in source (e.g. `Int32`, `String`,
    /// `[TodoItem]`, `Int32?`). Carries the optional sugar — the parser
    /// does not normalise `Optional<T>` to `T?` here; classification handles
    /// both shapes.
    public var swiftTypeText: String
    public var kind: ObservablePropertyKind
    /// `true` when the property was declared with `var`. Setters are only
    /// emitted for mutable properties.
    public var isMutable: Bool
    public init(
        name: String,
        swiftTypeText: String,
        kind: ObservablePropertyKind,
        isMutable: Bool
    ) {
        self.name = name
        self.swiftTypeText = swiftTypeText
        self.kind = kind
        self.isMutable = isMutable
    }
}

/// The classification used by `WireletObservableKotlinEmitter` to pick the
/// per-property render path (return type of `external fun nativeXxxTrack`,
/// Kotlin StateFlow value type, decode strategy).
///
/// Kept separate from `WireletObservableMacros.WireletObservableProperty.Kind`
/// (Sources/WireletObservableMacros/WireletObservableProperty.swift:3) so the
/// macro can keep its JNI-render closures and this enum can stay a plain
/// value carrying only schema-level facts.
public enum ObservablePropertyKind: Equatable, Sendable {
    /// `Int8 / Int16 / Int32 / UInt8 / UInt16 / Int64 / UInt32 / UInt64 /
    /// Bool / Float / Double`. The Swift type text drives the Kotlin
    /// mapping (`Int32` → `Int`, `Int64` → `Long`, etc.).
    case primitive
    /// `String`.
    case string
    /// A `@WireFormat`-annotated user struct/enum. `typeName` is the simple
    /// Swift identifier as written in source (no `Module.` prefix).
    case wireFormat(typeName: String)
    /// `[T]` where T is `@WireFormat`. `elementTypeName` mirrors `typeName`
    /// above. Primitive element arrays are not supported in v0.1 — the
    /// macro emits a diagnostic for them, and so does this schema (see
    /// Task 3).
    case wireFormatArray(elementTypeName: String)
    /// `Int8?` etc. — `Optional<T>` with primitive T. Same set as
    /// `.primitive` above.
    case optionalPrimitive
    /// `String?`.
    case optionalString
    /// `T?` where T is `@WireFormat`.
    case optionalWireFormat(typeName: String)
}

public struct ObservableMethod: Equatable, Sendable {
    public var name: String
    /// At v0.1 we support exactly two shapes: zero parameters, or one
    /// parameter whose type is a `@WireFormat` user type. Both forms are
    /// recorded as the parameter list as it appears in source — the
    /// emitter validates the shape.
    public var parameters: [ObservableMethodParameter]
    public init(name: String, parameters: [ObservableMethodParameter]) {
        self.name = name
        self.parameters = parameters
    }
}

public struct ObservableMethodParameter: Equatable, Sendable {
    /// The first (external) label as it appears in source. `_` is preserved
    /// — the emitter uses it to decide whether to drop the label when
    /// calling the wrapped function on the Swift side.
    public var label: String
    /// Swift type text as written in source (e.g. `TodoItem`).
    public var typeText: String
    public init(label: String, typeText: String) {
        self.label = label
        self.typeText = typeText
    }
}
```

- [ ] **Step 2: Confirm the file compiles**

Run: `swift build --target WireletObservableSchema`
Expected: `Build complete!` (the target compiles to an empty module that just declares value types).

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservableSchema/ObservableSchema.swift
git commit -m "feat(observable): add ObservableSchema model types"
```

### Task 3: Type classifier

**Files:**
- Create: `Sources/WireletObservableSchema/Internal/ObservableTypeClassifier.swift`

The classifier turns Swift type text into an `ObservablePropertyKind`. It mirrors `WireletObservableProperty.classify` (Sources/WireletObservableMacros/WireletObservableProperty.swift:46) but returns the schema-level kind instead of the macro-level render closures. Unsupported types (e.g. `[Int32]`) return `nil` — the parser surfaces those as a `ParseDiagnostic` rather than crashing.

- [ ] **Step 1: Write the classifier**

```swift
import Foundation

enum ObservableTypeClassifier {
    /// Returns the schema kind for a Swift type as written in source, or
    /// `nil` for unsupported shapes (primitive arrays, dictionaries, etc.).
    /// The caller (parser) is responsible for surfacing unsupported types
    /// to the user.
    static func classify(_ typeText: String) -> ObservablePropertyKind? {
        // Optional<T> normalization — both `T?` and `Optional<T>` accepted.
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
                .trimmingCharacters(in: .whitespaces)
            if element.contains(":") { return nil } // dictionaries unsupported in v0.1
            if isPrimitive(element) || element == "String" { return nil }
            return .wireFormatArray(elementTypeName: element)
        }
        if isPrimitive(typeText) {
            return .primitive
        }
        if typeText == "String" {
            return .string
        }
        // Anything else: treat as a user-defined @WireFormat type. The
        // emitter resolves it against the configured codec package.
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(_ inner: String) -> ObservablePropertyKind? {
        if isPrimitive(inner) { return .optionalPrimitive }
        if inner == "String" { return .optionalString }
        // Optional<[T]> / Optional<Optional<T>> are intentionally unsupported.
        if inner.hasPrefix("["), inner.hasSuffix("]") { return nil }
        if inner.hasSuffix("?") { return nil }
        if inner.hasPrefix("Optional<"), inner.hasSuffix(">") { return nil }
        return .optionalWireFormat(typeName: inner)
    }

    static func isPrimitive(_ typeText: String) -> Bool {
        switch typeText {
        case "Int8", "Int16", "Int32", "Int64",
             "UInt8", "UInt16", "UInt32", "UInt64",
             "Bool", "Float", "Double":
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: Compile**

Run: `swift build --target WireletObservableSchema`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservableSchema/Internal/ObservableTypeClassifier.swift
git commit -m "feat(observable): add ObservableTypeClassifier"
```

### Task 4: SwiftParser-based schema parser

**Files:**
- Create: `Sources/WireletObservableSchema/ObservableSchemaParser.swift`
- Create: `Tests/WireletObservableSchemaTests/Fixtures/CounterVM.swift`
- Create: `Tests/WireletObservableSchemaTests/Fixtures/TodoListVM.swift`
- Create: `Tests/WireletObservableSchemaTests/Fixtures/MixedDecls.swift`
- Create: `Tests/WireletObservableSchemaTests/ObservableSchemaParserTests.swift`

- [ ] **Step 1: Write the `CounterVM.swift` fixture**

`Tests/WireletObservableSchemaTests/Fixtures/CounterVM.swift`:

```swift
/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class CounterVM {
    public var count: Int32 = 0

    public init() {}

    @WireletExpose
    public func increment() {
        count += 1
    }
}
```

- [ ] **Step 2: Write the `TodoListVM.swift` fixture**

`Tests/WireletObservableSchemaTests/Fixtures/TodoListVM.swift`:

```swift
/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0
    public var pinned: TodoItem? = nil

    @ObservationIgnored
    public var debugLabel: String = ""

    public static let configKey: String = "todoList"

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

    public func unmarkedHelper() {
        // not @WireletExpose — must be skipped
    }
}
```

- [ ] **Step 3: Write the `MixedDecls.swift` fixture**

`Tests/WireletObservableSchemaTests/Fixtures/MixedDecls.swift`:

```swift
/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import Wirelet
import WireletObservable

@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool
}

@Observable
public final class PlainObservable {
    public var count: Int32 = 0
}

public final class Plain {}
```

- [ ] **Step 4: Write the parser**

`Sources/WireletObservableSchema/ObservableSchemaParser.swift`:

```swift
import Foundation
import SwiftParser
import SwiftSyntax

public enum ObservableSchemaParser {
    /// Parses the `@WireletObservable @Observable` view-models declared in a
    /// Swift source file. Declarations that lack either attribute or that
    /// are not classes are silently skipped — they belong to the existing
    /// wireformat emitter or are user code unrelated to this codegen.
    public static func parse(source: String, fileName: String) -> ObservableSchema {
        let tree = Parser.parse(source: source)
        let visitor = ObservableVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return ObservableSchema(viewModels: visitor.viewModels)
    }
}

final class ObservableVisitor: SyntaxVisitor {
    var viewModels: [ObservableViewModel] = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasAttribute(node.attributes, named: "WireletObservable") else {
            return .visitChildren
        }
        guard hasAttribute(node.attributes, named: "Observable") else {
            // Spec: only emit for classes carrying both. Bare `@WireletObservable`
            // is a macro-level diagnostic; at the schema layer we silently drop.
            return .visitChildren
        }
        let properties = collectProperties(of: node)
        let methods = collectExposedMethods(of: node)
        viewModels.append(ObservableViewModel(
            name: node.name.text,
            properties: properties,
            methods: methods
        ))
        return .visitChildren
    }

    private func collectProperties(of classDecl: ClassDeclSyntax) -> [ObservableProperty] {
        var out: [ObservableProperty] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains { mod in
                mod.name.text == "static" || mod.name.text == "class"
            }
            if isStatic { continue }
            if hasAttribute(varDecl.attributes, named: "ObservationIgnored") { continue }
            let isMutable = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
            for binding in varDecl.bindings {
                // Computed properties (with `{ get … }`) are skipped — observation
                // only tracks stored ones.
                guard binding.accessorBlock == nil else { continue }
                guard
                    let ident = binding.pattern.as(IdentifierPatternSyntax.self),
                    let typeAnno = binding.typeAnnotation
                else { continue }
                let typeText = typeAnno.type.trimmedDescription
                guard let kind = ObservableTypeClassifier.classify(typeText) else {
                    // Unsupported property type. v0.1: silently skip; the macro layer
                    // already reports it as a build-time diagnostic, so re-reporting
                    // here would double-fire. Leaving room for a future warning-level
                    // diagnostic carried on `ObservableSchema`.
                    continue
                }
                out.append(ObservableProperty(
                    name: ident.identifier.text,
                    swiftTypeText: typeText,
                    kind: kind,
                    isMutable: isMutable
                ))
            }
        }
        return out
    }

    private func collectExposedMethods(of classDecl: ClassDeclSyntax) -> [ObservableMethod] {
        var out: [ObservableMethod] = []
        for member in classDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard hasAttribute(funcDecl.attributes, named: "WireletExpose") else { continue }
            let params = funcDecl.signature.parameterClause.parameters.map { param in
                ObservableMethodParameter(
                    label: param.firstName.text,
                    typeText: param.type.trimmedDescription
                )
            }
            out.append(ObservableMethod(
                name: funcDecl.name.text,
                parameters: params
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

- [ ] **Step 5: Write the failing tests**

`Tests/WireletObservableSchemaTests/ObservableSchemaParserTests.swift`:

```swift
import Foundation
import Testing
@testable import WireletObservableSchema

@Test func parsesCounterVM() throws {
    let url = try #require(Bundle.module.url(
        forResource: "CounterVM",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "CounterVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.name == "CounterVM")
    #expect(vm.properties == [
        ObservableProperty(
            name: "count",
            swiftTypeText: "Int32",
            kind: .primitive,
            isMutable: true
        ),
    ])
    #expect(vm.methods == [
        ObservableMethod(name: "increment", parameters: []),
    ])
}

@Test func parsesTodoListVM() throws {
    let url = try #require(Bundle.module.url(
        forResource: "TodoListVM",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "TodoListVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.name == "TodoListVM")

    // configKey is static → skipped. debugLabel is @ObservationIgnored → skipped.
    // unmarkedHelper has no @WireletExpose → not in methods.
    #expect(vm.properties == [
        ObservableProperty(
            name: "items",
            swiftTypeText: "[TodoItem]",
            kind: .wireFormatArray(elementTypeName: "TodoItem"),
            isMutable: true
        ),
        ObservableProperty(
            name: "filter",
            swiftTypeText: "String",
            kind: .string,
            isMutable: true
        ),
        ObservableProperty(
            name: "totalCount",
            swiftTypeText: "Int32",
            kind: .primitive,
            isMutable: true
        ),
        ObservableProperty(
            name: "pinned",
            swiftTypeText: "TodoItem?",
            kind: .optionalWireFormat(typeName: "TodoItem"),
            isMutable: true
        ),
    ])
    #expect(vm.methods == [
        ObservableMethod(name: "add", parameters: [
            ObservableMethodParameter(label: "_", typeText: "TodoItem"),
        ]),
        ObservableMethod(name: "clear", parameters: []),
    ])
}

@Test func ignoresNonObservableDecls() throws {
    let url = try #require(Bundle.module.url(
        forResource: "MixedDecls",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "MixedDecls.swift")

    #expect(schema.viewModels.isEmpty)
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter WireletObservableSchemaTests`
Expected: 3 tests pass. If `parsesTodoListVM` fails on `pinned`, confirm the parser's type-text is exactly `TodoItem?` (no trailing whitespace). If `parsesCounterVM` fails because `vm.properties` is empty, check that `varDecl.bindings.count == 1` is not erroneously filtered (the parser intentionally does not gate on that).

- [ ] **Step 7: Commit**

```bash
git add Sources/WireletObservableSchema/ObservableSchemaParser.swift \
        Tests/WireletObservableSchemaTests/
git commit -m "feat(observable): add ObservableSchemaParser with VM/property/method discovery"
```

---

## Phase 2B: Kotlin emitter — config, type map, primitive bridge

### Task 5: Emitter config + entry point

**Files:**
- Create: `Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift`
- Create: `Sources/WireletObservableKotlinEmitter/ObservableKotlinEmitter.swift`

- [ ] **Step 1: Write the config**

`Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift`:

```swift
import Foundation
import WireletKotlinEmitter

/// JSON-decodable config for `emit-wirelet-observable`. Mirrors
/// `KotlinCodegenConfig` (Sources/WireletKotlinEmitter/KotlinCodegenConfig.swift:3)
/// but carries the observable-specific packages and JNI library name.
public struct ObservableCodegenConfig: Codable, Sendable, Equatable {
    /// Package the generated `<Name>ViewModel.kt` files land in.
    public var viewModelPackage: String
    /// Package the user-authored model classes (`TodoItem`, etc.) live in.
    /// Used to render `import <modelPackage>.<TypeName>` for every referenced
    /// `@WireFormat` user type.
    public var modelPackage: String
    /// Package the wireformat codecs live in. Used to render
    /// `import <codecPackage>.<TypeName>Codec` for setter/expose decoding
    /// and array decoding.
    public var codecPackage: String
    /// Package the `wirelet-observable-runtime` artifact exposes
    /// `WireletList` from. Defaults to
    /// `io.github.jiyimeta.wirelet.observable` per Phase 3's runtime
    /// package layout (spec line 244–249).
    public var runtimePackage: String
    /// `System.loadLibrary` argument. The consumer's Swift package, when
    /// cross-compiled to `aarch64-unknown-linux-android28`, produces a
    /// `lib<name>.so`; this string is `<name>`.
    public var libraryName: String
    /// Applied to the Swift class name before suffixing with `ViewModel`
    /// (e.g. `stripSuffix: "VM"` so `TodoListVM` → `TodoListViewModel`).
    /// Defaults to `identity` per the existing wireformat config.
    public var nameTransform: NameTransform

    public init(
        viewModelPackage: String,
        modelPackage: String,
        codecPackage: String,
        runtimePackage: String = "io.github.jiyimeta.wirelet.observable",
        libraryName: String,
        nameTransform: NameTransform = .identity
    ) {
        self.viewModelPackage = viewModelPackage
        self.modelPackage = modelPackage
        self.codecPackage = codecPackage
        self.runtimePackage = runtimePackage
        self.libraryName = libraryName
        self.nameTransform = nameTransform
    }

    private enum CodingKeys: String, CodingKey {
        case viewModelPackage
        case modelPackage
        case codecPackage
        case runtimePackage
        case libraryName
        case nameTransform
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewModelPackage = try c.decode(String.self, forKey: .viewModelPackage)
        modelPackage = try c.decode(String.self, forKey: .modelPackage)
        codecPackage = try c.decode(String.self, forKey: .codecPackage)
        runtimePackage = try c.decodeIfPresent(String.self, forKey: .runtimePackage)
            ?? "io.github.jiyimeta.wirelet.observable"
        libraryName = try c.decode(String.self, forKey: .libraryName)
        nameTransform = try c.decodeIfPresent(NameTransform.self, forKey: .nameTransform)
            ?? .identity
    }
}
```

- [ ] **Step 2: Write the emitter entry point (renders nothing yet)**

`Sources/WireletObservableKotlinEmitter/ObservableKotlinEmitter.swift`:

```swift
import WireletKotlinEmitter
import WireletObservableSchema

public struct ObservableKotlinEmitter: Sendable {
    public let config: ObservableCodegenConfig

    public init(config: ObservableCodegenConfig) {
        self.config = config
    }

    /// Renders one `<KotlinName>ViewModel.kt` file per view-model in the
    /// schema. Returns an empty list when the schema has no view-models.
    public func emit(schema: ObservableSchema) -> [KotlinFile] {
        schema.viewModels.map { vm in
            ViewModelEmitter.emit(vm, config: config)
        }
    }
}
```

The `ViewModelEmitter` entry point lands in Task 6. SwiftPM will error on the missing symbol at the next build step — that's expected; Task 6's first action satisfies it.

- [ ] **Step 3: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift \
        Sources/WireletObservableKotlinEmitter/ObservableKotlinEmitter.swift
git commit -m "feat(observable): add ObservableCodegenConfig + emitter entry"
```

### Task 6: Type map + `ViewModelEmitter` skeleton for primitive VMs

**Files:**
- Create: `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift`
- Create: `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift`

The skeleton handles only the primitive + ctor/release path. String / WireFormat / Optional / Array paths land in Task 8; method bridges land in Task 9. This split keeps each diff small and lets the Counter golden land before the TodoList one.

- [ ] **Step 1: Write the type map**

`Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift`:

```swift
import WireletObservableSchema

/// Per-property render plan used by `ViewModelEmitter`. Carries the Kotlin
/// type for the StateFlow value, the Kotlin signature of the
/// `nativeXxxTrack(self, Runnable)` external function, the same for
/// `nativeXxxSet`, and the StateFlow read expression that goes inside
/// `readXxxWithTracking()`.
enum ObservableKotlinTypeMap {
    struct Plan {
        /// The Kotlin spelling of the StateFlow value type
        /// (e.g. `Int`, `String`, `List<TodoItem>`, `TodoItem?`).
        let kotlinType: String
        /// The Kotlin return type of `nativeXxxTrack` (`Int`, `String`,
        /// `ByteArray`, …). Always non-nullable for non-Optional shapes —
        /// the JNI side returns the encoded payload directly.
        let nativeTrackReturn: String
        /// The Kotlin parameter type of `nativeXxxSet` after `self: Long, …`.
        /// `nil` for read-only / non-supported properties.
        let nativeSetParam: String?
        /// Expression that turns the value returned by `nativeXxxTrack(...)`
        /// into the StateFlow value. `$1` is replaced with the call
        /// expression. E.g. for `[TodoItem]` →
        /// `WireletList.decode($1, TodoItemCodec)`.
        let decodeTemplate: String
        /// Expression that encodes the new StateFlow value before passing
        /// it to `nativeXxxSet`. `$1` is the Kotlin value. E.g.
        /// `TodoItemCodec.encode($1)`.
        let encodeTemplate: String?
        /// Imports the per-property render path adds. Joined with the
        /// view-model's overall import set and deduped at file render.
        let extraImports: Set<String>
    }

    static func plan(
        for property: ObservableProperty,
        config: ObservableCodegenConfig
    ) -> Plan {
        switch property.kind {
        case .primitive:
            return primitivePlan(swiftType: property.swiftTypeText)
        case .string:
            return Plan(
                kotlinType: "String",
                nativeTrackReturn: "String",
                nativeSetParam: "String",
                decodeTemplate: "$1",
                encodeTemplate: "$1",
                extraImports: []
            )
        case let .wireFormat(typeName):
            let codec = config.nameTransform.apply(to: typeName) + "Codec"
            return Plan(
                kotlinType: config.nameTransform.apply(to: typeName),
                nativeTrackReturn: "ByteArray",
                nativeSetParam: "ByteArray",
                decodeTemplate: "\(codec).decode($1)",
                encodeTemplate: "\(codec).encode($1)",
                extraImports: [
                    "\(config.modelPackage).\(config.nameTransform.apply(to: typeName))",
                    "\(config.codecPackage).\(codec)",
                ]
            )
        case let .wireFormatArray(elementTypeName):
            let codec = config.nameTransform.apply(to: elementTypeName) + "Codec"
            let kotlin = "List<\(config.nameTransform.apply(to: elementTypeName))>"
            return Plan(
                kotlinType: kotlin,
                nativeTrackReturn: "ByteArray",
                // Setter for array properties: re-encode every element with
                // a length-prefix + count header. Matches the WireletList
                // shape (Phase 3 runtime).
                nativeSetParam: "ByteArray",
                decodeTemplate: "WireletList.decode($1, \(codec))",
                encodeTemplate: "WireletList.encode($1, \(codec))",
                extraImports: [
                    "\(config.modelPackage).\(config.nameTransform.apply(to: elementTypeName))",
                    "\(config.codecPackage).\(codec)",
                    "\(config.runtimePackage).WireletList",
                ]
            )
        case .optionalPrimitive:
            // Optional primitives transport as a 0-or-1-byte ByteArray:
            // null = absent, single byte = present, raw value following.
            // Matches the macro setter signature (jbyteArray?). The runtime
            // exposes `WireletOptional` helpers that this plan references.
            let inner = primitivePlan(swiftType: stripOptional(property.swiftTypeText))
            return Plan(
                kotlinType: "\(inner.kotlinType)?",
                nativeTrackReturn: "ByteArray?",
                nativeSetParam: "ByteArray?",
                decodeTemplate: "WireletOptional.decode\(inner.kotlinType)($1)",
                encodeTemplate: "WireletOptional.encode\(inner.kotlinType)($1)",
                extraImports: ["\(config.runtimePackage).WireletOptional"]
            )
        case .optionalString:
            return Plan(
                kotlinType: "String?",
                nativeTrackReturn: "String?",
                nativeSetParam: "String?",
                decodeTemplate: "$1",
                encodeTemplate: "$1",
                extraImports: []
            )
        case let .optionalWireFormat(typeName):
            let codec = config.nameTransform.apply(to: typeName) + "Codec"
            let kotlin = config.nameTransform.apply(to: typeName)
            return Plan(
                kotlinType: "\(kotlin)?",
                nativeTrackReturn: "ByteArray?",
                nativeSetParam: "ByteArray?",
                decodeTemplate: "$1?.let { \(codec).decode(it) }",
                encodeTemplate: "$1?.let { \(codec).encode(it) }",
                extraImports: [
                    "\(config.modelPackage).\(kotlin)",
                    "\(config.codecPackage).\(codec)",
                ]
            )
        }
    }

    /// Returns the JNI-symmetric Kotlin type + native shape for a Swift
    /// primitive type text. Mirrors the macro's marshaling rules table
    /// (spec line 211–224): `Int32` → `Int`, `Int64` → `Long`, `Bool` →
    /// `Boolean`, etc.
    static func primitivePlan(swiftType: String) -> Plan {
        let kotlin = kotlinPrimitive(swiftType: swiftType)
        return Plan(
            kotlinType: kotlin,
            nativeTrackReturn: kotlin,
            nativeSetParam: kotlin,
            decodeTemplate: "$1",
            encodeTemplate: "$1",
            extraImports: []
        )
    }

    static func kotlinPrimitive(swiftType: String) -> String {
        switch swiftType {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "Int"
        case "Int64", "UInt32", "UInt64": return "Long"
        case "Bool": return "Boolean"
        case "Float": return "Float"
        case "Double": return "Double"
        default: return swiftType
        }
    }

    private static func stripOptional(_ typeText: String) -> String {
        if typeText.hasSuffix("?") {
            return String(typeText.dropLast())
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            return String(typeText.dropFirst("Optional<".count).dropLast())
        }
        return typeText
    }
}
```

- [ ] **Step 2: Write the `ViewModelEmitter` skeleton (primitive-only)**

`Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift`:

```swift
import WireletKotlinEmitter
import WireletObservableSchema

enum ViewModelEmitter {
    /// Renders one `<KotlinName>ViewModel.kt` file for `vm`. The Kotlin
    /// class name is `<NameTransform.apply(vm.name)>ViewModel`. The file
    /// lands at `viewModelPackage / KotlinName.kt`.
    static func emit(
        _ vm: ObservableViewModel,
        config: ObservableCodegenConfig
    ) -> KotlinFile {
        let kotlinBase = config.nameTransform.apply(to: vm.name)
        let className = "\(kotlinBase)ViewModel"
        let path = config.viewModelPackage.replacingOccurrences(of: ".", with: "/")
            + "/\(className).kt"

        // Per-property render plans drive both the public StateFlow members
        // and the private external fun declarations.
        let plans: [(ObservableProperty, ObservableKotlinTypeMap.Plan)] =
            vm.properties.map { ($0, ObservableKotlinTypeMap.plan(for: $0, config: config)) }

        let imports = collectImports(vm: vm, plans: plans, config: config)
        let importsBlock = imports.sorted().map { "import \($0)" }.joined(separator: "\n")

        let stateFlowMembers = plans.map { prop, plan in
            stateFlowMember(property: prop, plan: plan)
        }.joined(separator: "\n\n")

        let trackHelpers = plans.map { prop, plan in
            trackHelper(property: prop, plan: plan, className: className)
        }.joined(separator: "\n\n")

        let externalTrackDecls = plans.map { prop, plan in
            "    private external fun \(nativeTrackFnName(prop)): \(plan.nativeTrackReturn)"
                .replacingOccurrences(of: nativeTrackFnName(prop),
                                      with: nativeTrackFnSignature(prop, plan: plan))
        }.joined(separator: "\n")

        let externalReleaseDecl = "    private external fun nativeRelease(self: Long)"

        let content = """
        // Auto-generated by emit-wirelet-observable. DO NOT EDIT.
        package \(config.viewModelPackage)

        \(importsBlock)

        class \(className) internal constructor(
            private val nativePtr: Long
        ) : ViewModel() {

        \(stateFlowMembers.isEmpty ? "" : stateFlowMembers + "\n")
        \(trackHelpers.isEmpty ? "" : trackHelpers + "\n")
            override fun onCleared() {
                nativeRelease(nativePtr)
                super.onCleared()
            }

        \(externalTrackDecls.isEmpty ? "" : externalTrackDecls + "\n")
        \(externalReleaseDecl)

            companion object {
                init { System.loadLibrary("\(config.libraryName)") }

                fun create(): \(className) =
                    \(className)(nativeNew())

                @JvmStatic
                private external fun nativeNew(): Long
            }
        }

        """
        return KotlinFile(relativePath: path, content: content)
    }

    // MARK: - Imports

    private static func collectImports(
        vm: ObservableViewModel,
        plans: [(ObservableProperty, ObservableKotlinTypeMap.Plan)],
        config: ObservableCodegenConfig
    ) -> Set<String> {
        var imports: Set<String> = [
            "androidx.lifecycle.ViewModel",
        ]
        if !plans.isEmpty {
            imports.formUnion([
                "androidx.lifecycle.viewModelScope",
                "kotlinx.coroutines.Dispatchers",
                "kotlinx.coroutines.flow.MutableStateFlow",
                "kotlinx.coroutines.flow.StateFlow",
                "kotlinx.coroutines.flow.asStateFlow",
                "kotlinx.coroutines.launch",
            ])
        }
        for (_, plan) in plans {
            imports.formUnion(plan.extraImports)
        }
        return imports
    }

    // MARK: - Member rendering

    private static func stateFlowMember(
        property: ObservableProperty,
        plan: ObservableKotlinTypeMap.Plan
    ) -> String {
        let initial = "read\(capitalised(property.name))WithTracking()"
        return """
            private val _\(property.name) = MutableStateFlow(\(initial))
            val \(property.name): StateFlow<\(plan.kotlinType)> = _\(property.name).asStateFlow()
        """
    }

    private static func trackHelper(
        property: ObservableProperty,
        plan: ObservableKotlinTypeMap.Plan,
        className: String
    ) -> String {
        let helperName = "read\(capitalised(property.name))WithTracking"
        let nativeFn = nativeTrackFnName(property)
        let nativeCall = "\(nativeFn)(nativePtr, Runnable {\n"
            + "                viewModelScope.launch(Dispatchers.Main) {\n"
            + "                    _\(property.name).value = \(helperName)()\n"
            + "                }\n"
            + "            })"
        let decoded = plan.decodeTemplate.replacingOccurrences(of: "$1", with: nativeCall)
        return """
            private fun \(helperName)(): \(plan.kotlinType) =
                \(decoded)
        """
    }

    // MARK: - Naming

    private static func nativeTrackFnName(_ property: ObservableProperty) -> String {
        "native\(capitalised(property.name))Track"
    }

    private static func nativeTrackFnSignature(
        _ property: ObservableProperty,
        plan: ObservableKotlinTypeMap.Plan
    ) -> String {
        "\(nativeTrackFnName(property))(self: Long, onChange: Runnable)"
    }

    static func capitalised(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
```

The skeleton intentionally lives at the level of "primitive-only Counter VM works". String / WireFormat / Optional bridging is already represented in the `Plan` table — they emit valid code already because the templates handle them — but the *test* added in Task 7 only locks in the Counter shape. Setters and `@WireletExpose` methods are not yet rendered; the TodoList golden (Task 9) drives that.

- [ ] **Step 3: Build**

Run: `swift build --target WireletObservableKotlinEmitter`
Expected: `Build complete!`. If `ObservableKotlinTypeMap.Plan` complains about Optional plan referencing `inner.kotlinType` outside an `if`, fix by inlining the recursive call result into a local before the `Plan(...)` initialiser.

- [ ] **Step 4: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/Internal/
git commit -m "feat(observable): add Kotlin type map + ViewModelEmitter skeleton"
```

### Task 7: Golden test — `CounterVM` → `CounterViewModel.kt`

**Files:**
- Create: `Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt`
- Create: `Tests/WireletObservableKotlinEmitterTests/CounterViewModelEmitterTests.swift`

- [ ] **Step 1: Write the expected golden file**

`Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt`:

```kotlin
// Auto-generated by emit-wirelet-observable. DO NOT EDIT.
package com.example.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class CounterViewModel internal constructor(
    private val nativePtr: Long
) : ViewModel() {

    private val _count = MutableStateFlow(readCountWithTracking())
    val count: StateFlow<Int> = _count.asStateFlow()

    private fun readCountWithTracking(): Int =
        nativeCountTrack(nativePtr, Runnable {
            viewModelScope.launch(Dispatchers.Main) {
                _count.value = readCountWithTracking()
            }
        })

    override fun onCleared() {
        nativeRelease(nativePtr)
        super.onCleared()
    }

    private external fun nativeCountTrack(self: Long, onChange: Runnable): Int
    private external fun nativeRelease(self: Long)

    companion object {
        init { System.loadLibrary("CounterJNI") }

        fun create(): CounterViewModel =
            CounterViewModel(nativeNew())

        @JvmStatic
        private external fun nativeNew(): Long
    }
}
```

Note the `CounterVM` → `CounterViewModel` rename: the test uses `nameTransform: .stripSuffix("VM")` so the Swift `CounterVM` becomes the Kotlin base `Counter`, then the emitter appends `ViewModel`.

- [ ] **Step 2: Write the failing test**

`Tests/WireletObservableKotlinEmitterTests/CounterViewModelEmitterTests.swift`:

```swift
import Foundation
import Testing
@testable import WireletObservableKotlinEmitter
import WireletKotlinEmitter
import WireletObservableSchema

@Test func emitsCounterViewModel() throws {
    let vm = ObservableViewModel(
        name: "CounterVM",
        properties: [
            ObservableProperty(
                name: "count",
                swiftTypeText: "Int32",
                kind: .primitive,
                isMutable: true
            ),
        ],
        methods: []
    )
    let config = ObservableCodegenConfig(
        viewModelPackage: "com.example.app.viewmodels",
        modelPackage: "com.example.app.model",
        codecPackage: "com.example.app.codecs",
        libraryName: "CounterJNI",
        nameTransform: .stripSuffix("VM")
    )

    let files = ObservableKotlinEmitter(config: config)
        .emit(schema: ObservableSchema(viewModels: [vm]))

    #expect(files.count == 1)
    let actual = try #require(files.first)
    #expect(actual.relativePath ==
        "com/example/app/viewmodels/CounterViewModel.kt")

    let url = try #require(Bundle.module.url(
        forResource: "CounterViewModel.expected",
        withExtension: "kt",
        subdirectory: "Fixtures"
    ))
    let expected = try String(contentsOf: url, encoding: .utf8)
    if actual.content != expected {
        Issue.record("""
        Golden mismatch. Diff:
        --- expected
        +++ actual
        \(diff(expected: expected, actual: actual.content))
        """)
    }
}

/// Tiny line-oriented diff for clearer test failure output.
private func diff(expected: String, actual: String) -> String {
    let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    let n = max(e.count, a.count)
    for i in 0..<n {
        let l = i < e.count ? String(e[i]) : "<EOF>"
        let r = i < a.count ? String(a[i]) : "<EOF>"
        if l != r {
            out.append("L\(i + 1):")
            out.append("- \(l)")
            out.append("+ \(r)")
        }
    }
    return out.joined(separator: "\n")
}
```

- [ ] **Step 3: Run the test and fix whitespace drift until it passes**

Run: `swift test --filter WireletObservableKotlinEmitterTests.emitsCounterViewModel`
Expected on first run: likely fails. The emitter template in Task 6 was written by hand against the golden; small whitespace differences (trailing newlines on the empty sections, blank-line collapses around the omitted `setter` section) are normal. Fix by adjusting the template literal in `ViewModelEmitter.swift` until the diff is empty.

- [ ] **Step 4: Commit**

```bash
git add Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt \
        Tests/WireletObservableKotlinEmitterTests/CounterViewModelEmitterTests.swift \
        Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift
git commit -m "test(observable): golden Counter VM emission via primitive bridge"
```

---

## Phase 2C: Setters + exposed-method bridges + full TodoListVM golden

### Task 8: Setters + exposed-method rendering

**Files:**
- Modify: `Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift`

- [ ] **Step 1: Add the setter renderer**

In `ViewModelEmitter`, add a helper that produces `external fun nativeXxxSet(self: Long, value: T)` decls and an internal `update<Xxx>(value: T)` wrapper. Mutable properties are the ones from `vm.properties` whose `isMutable` is `true` *and* whose plan has a non-nil `nativeSetParam`.

```swift
private static func setterWrapper(
    property: ObservableProperty,
    plan: ObservableKotlinTypeMap.Plan
) -> String? {
    guard property.isMutable, let nativeParam = plan.nativeSetParam,
          let encodeTpl = plan.encodeTemplate
    else { return nil }
    _ = nativeParam // referenced via the external decl
    let encoded = encodeTpl.replacingOccurrences(of: "$1", with: "value")
    let nativeFn = "native\(capitalised(property.name))Set"
    return """
        fun update\(capitalised(property.name))(value: \(plan.kotlinType)) {
            \(nativeFn)(nativePtr, \(encoded))
        }
    """
}

private static func setterExternalDecl(
    property: ObservableProperty,
    plan: ObservableKotlinTypeMap.Plan
) -> String? {
    guard property.isMutable, let nativeParam = plan.nativeSetParam else { return nil }
    let nativeFn = "native\(capitalised(property.name))Set"
    return "    private external fun \(nativeFn)(self: Long, value: \(nativeParam))"
}
```

- [ ] **Step 2: Add the exposed-method renderer**

```swift
private static func methodWrapper(
    method: ObservableMethod,
    config: ObservableCodegenConfig
) -> (publicFn: String, externalDecl: String, extraImports: Set<String>)? {
    switch method.parameters.count {
    case 0:
        let nativeFn = "native\(capitalised(method.name))"
        let publicFn = """
            fun \(method.name)() = \(nativeFn)(nativePtr)
        """
        let external = "    private external fun \(nativeFn)(self: Long)"
        return (publicFn, external, [])
    case 1:
        let param = method.parameters[0]
        // Only @WireFormat-typed single-arg methods are supported at the
        // macro layer; mirror that here (matches macro
        // `renderInvoke` rejection of primitives + String —
        // Sources/WireletObservableMacros/WireletObservableMacro.swift:485).
        let swiftType = param.typeText
        if ObservableTypeClassifierBridge.isPrimitive(swiftType) || swiftType == "String" {
            return nil
        }
        let codec = config.nameTransform.apply(to: swiftType) + "Codec"
        let kotlinType = config.nameTransform.apply(to: swiftType)
        let nativeFn = "native\(capitalised(method.name))"
        let publicFn = """
            fun \(method.name)(\(callArgLabel(of: param)): \(kotlinType)) =
                \(nativeFn)(nativePtr, \(codec).encode(\(callArgLabel(of: param))))
        """
        let external = "    private external fun \(nativeFn)(self: Long, arg0: ByteArray)"
        let imports: Set<String> = [
            "\(config.modelPackage).\(kotlinType)",
            "\(config.codecPackage).\(codec)",
        ]
        return (publicFn, external, imports)
    default:
        // >1 params is unsupported at the macro layer too — skip.
        return nil
    }
}

private static func callArgLabel(of param: ObservableMethodParameter) -> String {
    // `_` → invent a name; otherwise keep the source label as the Kotlin
    // parameter name. The wrapper has only one arg so `arg0` is safe.
    param.label == "_" ? "arg0" : param.label
}
```

`ObservableTypeClassifierBridge` is a tiny shim that re-exports the `isPrimitive` predicate from `WireletObservableSchema`. Add it to the same file:

```swift
private enum ObservableTypeClassifierBridge {
    static func isPrimitive(_ s: String) -> Bool {
        switch s {
        case "Int8", "Int16", "Int32", "Int64",
             "UInt8", "UInt16", "UInt32", "UInt64",
             "Bool", "Float", "Double":
            return true
        default:
            return false
        }
    }
}
```

(We could expose `ObservableTypeClassifier.isPrimitive` publicly from `WireletObservableSchema` instead, but it stays internal so the schema target's surface is just the model types + parser entry point. The shim duplicates seven cases — acceptable.)

- [ ] **Step 3: Wire the new renderers into `emit`**

Edit the `static func emit(...)` body so the assembled `content` string also includes:
- the `setterWrappers` block right after `trackHelpers`,
- the `methodWrappers` block right after `setterWrappers`,
- the `setterExternalDecls` block right after `externalTrackDecls`,
- the `methodExternalDecls` block right after `setterExternalDecls`,
- the `extraImports` from method wrappers folded into the import set in `collectImports`.

Concrete patch:

```swift
let setterWrappers = plans.compactMap { prop, plan in
    setterWrapper(property: prop, plan: plan)
}.joined(separator: "\n\n")

let setterExternalDecls = plans.compactMap { prop, plan in
    setterExternalDecl(property: prop, plan: plan)
}.joined(separator: "\n")

let methodRenders = vm.methods.compactMap { method in
    methodWrapper(method: method, config: config)
}
let methodWrappers = methodRenders.map(\.publicFn).joined(separator: "\n\n")
let methodExternalDecls = methodRenders.map(\.externalDecl).joined(separator: "\n")
let methodImports = methodRenders.reduce(into: Set<String>()) { acc, r in
    acc.formUnion(r.extraImports)
}
```

Then in `collectImports`, take `methodImports` as an extra parameter and union it in.

The final `content` literal becomes:

```swift
let content = """
// Auto-generated by emit-wirelet-observable. DO NOT EDIT.
package \(config.viewModelPackage)

\(importsBlock)

class \(className) internal constructor(
    private val nativePtr: Long
) : ViewModel() {

\(joinBlock(stateFlowMembers))\
\(joinBlock(trackHelpers))\
\(joinBlock(setterWrappers))\
\(joinBlock(methodWrappers))\
    override fun onCleared() {
        nativeRelease(nativePtr)
        super.onCleared()
    }

\(joinBlock(externalTrackDecls, trailing: false))\
\(joinBlock(setterExternalDecls, trailing: false))\
\(joinBlock(methodExternalDecls, trailing: false))\
    private external fun nativeRelease(self: Long)

    companion object {
        init { System.loadLibrary("\(config.libraryName)") }

        fun create(): \(className) =
            \(className)(nativeNew())

        @JvmStatic
        private external fun nativeNew(): Long
    }
}

"""
```

`joinBlock` is a small helper that adds a trailing `\n\n` (members) or `\n` (decls) only when the block is non-empty:

```swift
private static func joinBlock(_ block: String, trailing: Bool = true) -> String {
    if block.isEmpty { return "" }
    return trailing ? "\(block)\n\n" : "\(block)\n"
}
```

- [ ] **Step 4: Rerun the Counter golden test**

Run: `swift test --filter WireletObservableKotlinEmitterTests.emitsCounterViewModel`
Expected: still passes — Counter's only mutable property is `count: Int32` whose setter wrapper renders. **The Counter golden does NOT include a setter** because real consumers mutate via `@WireletExpose`-d methods, not setters; the Counter spec example matches that pattern. Update the Counter golden to include the new `updateCount` block and the `nativeCountSet` external decl. Lock the new shape:

```kotlin
class CounterViewModel internal constructor(
    private val nativePtr: Long
) : ViewModel() {

    private val _count = MutableStateFlow(readCountWithTracking())
    val count: StateFlow<Int> = _count.asStateFlow()

    private fun readCountWithTracking(): Int =
        nativeCountTrack(nativePtr, Runnable {
            viewModelScope.launch(Dispatchers.Main) {
                _count.value = readCountWithTracking()
            }
        })

    fun updateCount(value: Int) {
        nativeCountSet(nativePtr, value)
    }

    override fun onCleared() {
        nativeRelease(nativePtr)
        super.onCleared()
    }

    private external fun nativeCountTrack(self: Long, onChange: Runnable): Int
    private external fun nativeCountSet(self: Long, value: Int)
    private external fun nativeRelease(self: Long)

    companion object {
        init { System.loadLibrary("CounterJNI") }

        fun create(): CounterViewModel =
            CounterViewModel(nativeNew())

        @JvmStatic
        private external fun nativeNew(): Long
    }
}
```

Edit `Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt` to match.

- [ ] **Step 5: Verify the test still passes after the golden update**

Run: `swift test --filter WireletObservableKotlinEmitterTests.emitsCounterViewModel`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/Internal/ViewModelEmitter.swift \
        Tests/WireletObservableKotlinEmitterTests/Fixtures/CounterViewModel.expected.kt
git commit -m "feat(observable): emit setters + @WireletExpose method bridges in Kotlin VMs"
```

### Task 9: Golden test — `TodoListVM` → `TodoListViewModel.kt`

**Files:**
- Create: `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt`
- Create: `Tests/WireletObservableKotlinEmitterTests/TodoListViewModelEmitterTests.swift`

This task locks in the spec's full example (spec line 235–314) modulo the spec's intentional omissions (no setter wrappers in the spec; methods + state flows only). Our emitter goes slightly further — it emits setter wrappers for every mutable property because the macro layer emits the matching `__<prop>_set` JNI symbols. The golden below reflects what the emitter actually produces, not the abridged spec snippet.

- [ ] **Step 1: Bootstrap the golden file**

Write `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt` as a placeholder containing only a header line (so the test fixture loader resolves it). After Step 3 below runs the emitter and dumps the actual output, replace the placeholder with the dumped content verbatim — the same bootstrap pattern as the macro golden in Phase 1 Task 13 (Sources/.../TodoListMacroExpansionTests.swift). The intent: avoid hand-counting whitespace.

Placeholder content:

```kotlin
// PLACEHOLDER — overwritten by bootstrap step in Task 9
```

- [ ] **Step 2: Write the failing test**

`Tests/WireletObservableKotlinEmitterTests/TodoListViewModelEmitterTests.swift`:

```swift
import Foundation
import Testing
@testable import WireletObservableKotlinEmitter
import WireletKotlinEmitter
import WireletObservableSchema

@Test func emitsTodoListViewModel() throws {
    let vm = ObservableViewModel(
        name: "TodoListVM",
        properties: [
            ObservableProperty(
                name: "items",
                swiftTypeText: "[TodoItem]",
                kind: .wireFormatArray(elementTypeName: "TodoItem"),
                isMutable: true
            ),
            ObservableProperty(
                name: "filter",
                swiftTypeText: "String",
                kind: .string,
                isMutable: true
            ),
            ObservableProperty(
                name: "totalCount",
                swiftTypeText: "Int32",
                kind: .primitive,
                isMutable: true
            ),
            ObservableProperty(
                name: "pinned",
                swiftTypeText: "TodoItem?",
                kind: .optionalWireFormat(typeName: "TodoItem"),
                isMutable: true
            ),
        ],
        methods: [
            ObservableMethod(name: "add", parameters: [
                ObservableMethodParameter(label: "_", typeText: "TodoItem"),
            ]),
            ObservableMethod(name: "clear", parameters: []),
        ]
    )
    let config = ObservableCodegenConfig(
        viewModelPackage: "io.github.jiyimeta.observablecounter.generated",
        modelPackage: "io.github.jiyimeta.observablecounter",
        codecPackage: "io.github.jiyimeta.observablecounter.codecs",
        libraryName: "ObservableCounterJNI",
        nameTransform: .stripSuffix("VM")
    )

    let files = ObservableKotlinEmitter(config: config)
        .emit(schema: ObservableSchema(viewModels: [vm]))

    #expect(files.count == 1)
    let actual = try #require(files.first)
    #expect(actual.relativePath ==
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt")

    let url = try #require(Bundle.module.url(
        forResource: "TodoListViewModel.expected",
        withExtension: "kt",
        subdirectory: "Fixtures"
    ))
    let expected = try String(contentsOf: url, encoding: .utf8)
    if actual.content != expected {
        // Dump actual to /tmp during bootstrap so the golden can be lifted
        // wholesale on first run.
        try? actual.content.write(
            toFile: "/tmp/TodoListViewModel.actual.kt",
            atomically: true,
            encoding: .utf8
        )
        Issue.record("""
        Golden mismatch. Actual written to /tmp/TodoListViewModel.actual.kt.
        Copy it into Fixtures/TodoListViewModel.expected.kt once the shape is right.
        """)
    }
}
```

- [ ] **Step 3: Run the test, inspect the actual output, lift the golden**

Run: `swift test --filter WireletObservableKotlinEmitterTests.emitsTodoListViewModel`
Expected: FAIL (placeholder mismatch). Open `/tmp/TodoListViewModel.actual.kt` and **manually verify** each section:

1. **Package + imports.** Must include `io.github.jiyimeta.observablecounter.TodoItem`, `…codecs.TodoItemCodec`, `io.github.jiyimeta.wirelet.observable.WireletList`, the standard `androidx.lifecycle.*` + `kotlinx.coroutines.*` set. No duplicates.
2. **StateFlow members.** `items: StateFlow<List<TodoItem>>`, `filter: StateFlow<String>`, `totalCount: StateFlow<Int>`, `pinned: StateFlow<TodoItem?>`.
3. **Track helpers.** Each helper calls `nativeXxxTrack(nativePtr, Runnable { ... })`. The `pinned` decoder must include `?.let { TodoItemCodec.decode(it) }`. The `items` decoder must include `WireletList.decode(<call>, TodoItemCodec)`.
4. **Setter wrappers.** One `updateItems(value: List<TodoItem>) { nativeItemsSet(nativePtr, WireletList.encode(value, TodoItemCodec)) }`. One `updateFilter(value: String)`, one `updateTotalCount(value: Int)`, one `updatePinned(value: TodoItem?)` passing `value?.let { TodoItemCodec.encode(it) }`.
5. **Method wrappers.** `fun add(arg0: TodoItem) = nativeAdd(nativePtr, TodoItemCodec.encode(arg0))` and `fun clear() = nativeClear(nativePtr)`.
6. **External fun decls.** `nativeItemsTrack(self: Long, onChange: Runnable): ByteArray`; `nativeFilterTrack(... ): String`; `nativeTotalCountTrack(... ): Int`; `nativePinnedTrack(... ): ByteArray?`; `nativeItemsSet(self: Long, value: ByteArray)`; `nativeFilterSet(self: Long, value: String)`; `nativeTotalCountSet(self: Long, value: Int)`; `nativePinnedSet(self: Long, value: ByteArray?)`; `nativeAdd(self: Long, arg0: ByteArray)`; `nativeClear(self: Long)`; `nativeRelease(self: Long)`.
7. **Companion** with `System.loadLibrary("ObservableCounterJNI")` + `nativeNew(): Long`.

If any section is wrong (a missing import, a duplicated entry, a stray comma), fix `ViewModelEmitter` or `ObservableKotlinTypeMap`, rerun, and re-inspect. Only once the actual output passes all seven checks above: copy `/tmp/TodoListViewModel.actual.kt` into `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt`.

- [ ] **Step 4: Lock the golden — rerun the test**

Run: `swift test --filter WireletObservableKotlinEmitterTests.emitsTodoListViewModel`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt \
        Tests/WireletObservableKotlinEmitterTests/TodoListViewModelEmitterTests.swift \
        Sources/WireletObservableKotlinEmitter/
git commit -m "test(observable): golden full TodoListVM emission"
```

---

## Phase 2D: CLI

### Task 10: `emit-wirelet-observable` CLI

**Files:**
- Create: `Sources/EmitWireletObservable/main.swift`

The CLI mirrors `EmitWireletKotlin/main.swift` line-for-line, with three differences: the config type is `ObservableCodegenConfig`, the emitter type is `ObservableKotlinEmitter`, and the schema parser is `ObservableSchemaParser`. Filtering by `--include-package` matches the existing semantic — filter by the Kotlin package of the file's relative path.

- [ ] **Step 1: Write `main.swift`**

```swift
import Foundation
import WireletKotlinEmitter
import WireletObservableKotlinEmitter
import WireletObservableSchema

struct CLIArguments {
    var configPath: String
    var sourceDir: String
    var outputDir: String
    /// Same semantics as `emit-wirelet-kotlin --include-package` —
    /// filters generated files by the Kotlin package of their relative
    /// path. Multi-module Gradle builds use this to assign disjoint
    /// view-model packages to disjoint modules from one schema source.
    var includePackages: Set<String>

    static func parse(_ argv: [String]) -> CLIArguments? {
        var config: String?
        var source: String?
        var output: String?
        var includePackages = Set<String>()
        var i = 1
        while i < argv.count {
            let key = argv[i]
            switch key {
            case "--config": config = argv[safe: i + 1]; i += 2
            case "--source": source = argv[safe: i + 1]; i += 2
            case "--output": output = argv[safe: i + 1]; i += 2
            case "--include-package":
                if let pkg = argv[safe: i + 1] { includePackages.insert(pkg) }
                i += 2
            default:
                writeStderr("Unknown argument: \(key)\n")
                return nil
            }
        }
        guard let c = config, let s = source, let o = output else { return nil }
        return CLIArguments(
            configPath: c,
            sourceDir: s,
            outputDir: o,
            includePackages: includePackages
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func writeStderr(_ s: String) {
    FileHandle.standardError.write(Data(s.utf8))
}

guard let args = CLIArguments.parse(CommandLine.arguments) else {
    writeStderr("""
    usage: emit-wirelet-observable --config <file> --source <dir> --output <dir> \
    [--include-package <name>]...
    """)
    exit(2)
}

let configURL = URL(fileURLWithPath: args.configPath)
let configData = try Data(contentsOf: configURL)
let config = try JSONDecoder().decode(ObservableCodegenConfig.self, from: configData)

let sourceURL = URL(fileURLWithPath: args.sourceDir, isDirectory: true)
var aggregateSchema = ObservableSchema(viewModels: [])
if let enumerator = FileManager.default.enumerator(
    at: sourceURL,
    includingPropertiesForKeys: [.isRegularFileKey]
) {
    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        let schema = ObservableSchemaParser.parse(source: source, fileName: url.lastPathComponent)
        aggregateSchema.viewModels.append(contentsOf: schema.viewModels)
    }
}

let emitter = ObservableKotlinEmitter(config: config)
let allFiles = emitter.emit(schema: aggregateSchema)

func kotlinPackage(of relativePath: String) -> String {
    let dir = (relativePath as NSString).deletingLastPathComponent
    return dir.replacingOccurrences(of: "/", with: ".")
}

let files: [KotlinFile] = args.includePackages.isEmpty
    ? allFiles
    : allFiles.filter { args.includePackages.contains(kotlinPackage(of: $0.relativePath)) }

let outputURL = URL(fileURLWithPath: args.outputDir, isDirectory: true)

var generatedPaths = Set<String>()
for file in files {
    let dest = outputURL.appendingPathComponent(file.relativePath)
    try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == file.content {
        // Idempotent — skip rewrite.
    } else {
        try file.content.write(to: dest, atomically: true, encoding: .utf8)
    }
    generatedPaths.insert(dest.resolvingSymlinksInPath().path)
}

if let sweep = FileManager.default.enumerator(at: outputURL, includingPropertiesForKeys: nil) {
    for case let url as URL in sweep {
        let resolved = url.resolvingSymlinksInPath().path
        guard url.pathExtension == "kt", !generatedPaths.contains(resolved) else { continue }
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Build the executable**

Run: `swift build --product emit-wirelet-observable`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/EmitWireletObservable/main.swift
git commit -m "feat(observable): add emit-wirelet-observable CLI"
```

### Task 11: CLI integration test

**Files:**
- Create: `Tests/EmitWireletObservableTests/Fixtures/observable-codegen.json`
- Create: `Tests/EmitWireletObservableTests/Fixtures/sources/TodoListVM.swift`
- Create: `Tests/EmitWireletObservableTests/Fixtures/sources/TodoItem.swift`
- Create: `Tests/EmitWireletObservableTests/CLISmokeTests.swift`

- [ ] **Step 1: Write the config fixture**

`Tests/EmitWireletObservableTests/Fixtures/observable-codegen.json`:

```json
{
  "viewModelPackage": "io.github.jiyimeta.observablecounter.generated",
  "modelPackage": "io.github.jiyimeta.observablecounter",
  "codecPackage": "io.github.jiyimeta.observablecounter.codecs",
  "libraryName": "ObservableCounterJNI",
  "nameTransform": { "stripSuffix": "VM" }
}
```

- [ ] **Step 2: Write the source fixtures**

`Tests/EmitWireletObservableTests/Fixtures/sources/TodoItem.swift`:

```swift
import Wirelet

@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool
}
```

`Tests/EmitWireletObservableTests/Fixtures/sources/TodoListVM.swift`:

```swift
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0
    public var pinned: TodoItem? = nil

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

- [ ] **Step 3: Write the CLI test**

`Tests/EmitWireletObservableTests/CLISmokeTests.swift`:

```swift
import Foundation
import Testing

@Test func cliEmitsTodoListViewModel() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("observable-codegen.json")

    // ~/Library/Caches — same rationale as in EmitWireletKotlinTests/CLISmokeTests.swift
    // (avoid /var/folders sandboxing that hides writes from the parent process).
    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-observable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-observable")
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)

    let expectedPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt"
    )
    #expect(FileManager.default.fileExists(atPath: expectedPath.path))

    // Idempotency: second run preserves mtime.
    let firstMtime = try mtime(of: expectedPath)
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)
    let secondMtime = try mtime(of: expectedPath)
    #expect(firstMtime == secondMtime)
}

@Test func cliIncludePackageFiltersOutput() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("observable-codegen.json")

    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-observable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-observable")

    // Filtering by a non-matching package emits zero files.
    try runCLI(
        executable: executable, config: configPath, source: sourcesDir, output: outputDir,
        includePackages: ["io.example.other"]
    )
    let viewModelPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt"
    )
    #expect(!FileManager.default.fileExists(atPath: viewModelPath.path))

    // Matching package emits the expected file.
    try runCLI(
        executable: executable, config: configPath, source: sourcesDir, output: outputDir,
        includePackages: ["io.github.jiyimeta.observablecounter.generated"]
    )
    #expect(FileManager.default.fileExists(atPath: viewModelPath.path))
}

private func productsURL() -> URL {
    let testBundle = Bundle.module.bundleURL
    return testBundle.deletingLastPathComponent()
}

private func runCLI(
    executable: URL,
    config: URL,
    source: URL,
    output: URL,
    includePackages: [String] = []
) throws {
    let process = Process()
    process.executableURL = executable
    var args = [
        "--config", config.path,
        "--source", source.path,
        "--output", output.path,
    ]
    for pkg in includePackages {
        args.append("--include-package")
        args.append(pkg)
    }
    process.arguments = args
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8) ?? ""
        Issue.record("CLI failed: \(msg)")
    }
}

private func mtime(of url: URL) throws -> Date {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return attrs[.modificationDate] as? Date ?? .distantPast
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter EmitWireletObservableTests`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tests/EmitWireletObservableTests/
git commit -m "test(observable): CLI smoke (emit + filter + idempotent)"
```

---

## Phase 2E: Full-suite verification

### Task 12: Run the entire test suite + lint

**Files:** (none — verification only)

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: every previously-passing test still passes, plus the 3 + 2 + 2 new tests from Tasks 4, 7, 9, 11. No new warnings.

If a Phase 1 macro test starts failing because of a SwiftSyntax / SwiftParser version mismatch surfaced by the new `WireletObservableSchema` target, pin both targets to the same `SwiftParser` product import (already done — both depend on `swift-syntax`).

- [ ] **Step 2: Build for release**

Run: `swift build -c release`
Expected: `Build complete!`. Confirms the new CLI executable can be produced with optimisations on.

- [ ] **Step 3: Apple linker hygiene check**

Run: `swift build --target WireletObservableKotlinEmitter --target WireletObservableSchema`
Expected: no `@_cdecl` symbols leak (the emitter is host-side codegen — there should be no JNI symbols at all). Confirm with:

```bash
nm .build/debug/WireletObservableKotlinEmitter.o 2>/dev/null | grep ' T _WireletObservable_' || echo OK
```

Expected output: `OK`.

- [ ] **Step 4: Commit (only if anything was tweaked)**

If Steps 1–3 surfaced any small fixes (formatter, doc comment, dead import), commit them under:

```bash
git commit -m "chore(observable): wrap up Phase 2 verification fixes"
```

If nothing needed touching, skip the commit.

---

## Self-review checklist (done)

- **Spec coverage** — Phase 2 covers spec §"Phase 3 — Schema parser + Kotlin emitter + CLI" (line 512–516) end to end: `WireletObservableSchema` (Tasks 2–4), `WireletObservableKotlinEmitter` (Tasks 5–9), `EmitWireletObservable` CLI (Tasks 10–11), with golden tests for `TodoListVM` (Task 9) and the primitive-only counter (Task 7), and a CLI integration test that writes generated `.kt` to a temp directory (Task 11).
- **Out-of-scope discipline** — `kotlin/observable-runtime/` (`WireletList`, `WireletOptional`), the Gradle plugin DSL, and the Android example are explicitly deferred. The emitter *references* `WireletList` / `WireletOptional` in generated imports (the spec's emit-side contract requires that), but neither type ships in this plan — that's why the generated VMs do not compile against a real Gradle module yet; Phase 3 plan provides those types.
- **Placeholders** — Task 7 / Task 9 explicitly bootstrap the golden file by running the emitter once and lifting the actual output rather than hand-writing the whitespace. This is intentional: the alternative ("paste the expected string before running") risks an off-by-one whitespace mismatch in a 60-line Kotlin file. Step-3 of Task 9 lists the seven correctness checks the human runs against the bootstrap output before locking the golden.
- **Type consistency** — `ObservablePropertyKind` cases used across Tasks 2, 3, 4, 6, 8, 9 are spelled identically (`primitive` / `string` / `wireFormat(typeName:)` / `wireFormatArray(elementTypeName:)` / `optionalPrimitive` / `optionalString` / `optionalWireFormat(typeName:)`). The emitter's `Plan` fields (`kotlinType`, `nativeTrackReturn`, `nativeSetParam`, `decodeTemplate`, `encodeTemplate`, `extraImports`) are populated for every Kind in Task 6 and consumed in Task 8.
- **Naming consistency** — Native JNI Kotlin function names follow `native<PascalProp>Track`, `native<PascalProp>Set`, `native<PascalMethod>`, and `nativeNew` / `nativeRelease`. These are the Kotlin-side names; the macro emits `@_cdecl("WireletObservable_<Class>_<member>_track|_set|_invoke|_new|_release")` symbols. The mapping between them is the `external fun` Kotlin name → JVM JNI-symbol mangling, which uses the `external fun` Kotlin name. The macro and the emitter were aligned in Phase 1; Phase 2 doesn't introduce new bridge symbols.
- **Scope** — Single subsystem (Kotlin codegen). Independent of the Kotlin runtime artifact and the Gradle plugin. Can be merged on its own — the generated `.kt` files will not yet compile against any Gradle project until Phase 3 ships `wirelet-observable-runtime`, but the codegen contract is locked.

---

## What lands after this plan

This plan ships the Swift-side codegen. After Phase 2 is on `main`:

1. **Phase 3 plan** — `kotlin/observable-runtime/` Gradle module (`WireletList`, `WireletOptional`, `JObjectGlobalRef` Runnable adapter), plus the `kotlin/gradle-plugin/` `observable` DSL block driving `generateWireletObservableViewModels`. End of Phase 3, a real Kotlin project can compile the generated `<Name>ViewModel.kt`.
2. **Phase 4 plan** — `examples/observable-counter/` end-to-end with Android emulator smoke; extends `examples.yml` CI matrix.
3. **Phase 5 plan** — README + `v0.2.0` publish wiring `wirelet-observable-runtime` into `publish.yml`.
