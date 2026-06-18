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
        returnTypeText: String?,
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
