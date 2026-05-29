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
