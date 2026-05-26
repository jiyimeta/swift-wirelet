import Foundation

/// In-memory description of all `@WireFormat`-family declarations
/// discovered in a set of Swift source files.
public struct Schema: Equatable, Sendable {
    public var types: [WireType]
    public init(types: [WireType]) {
        self.types = types
    }
}

/// One discovered declaration. Either a struct (`@WireFormat`),
/// a sum-type enum (`@WireFormatChoice`), or a raw enum
/// (`@WireFormatEnum`).
public enum WireType: Equatable, Sendable {
    case `struct`(WireStruct)
    case choice(WireChoice)
    case rawEnum(WireRawEnum)

    public var name: String {
        switch self {
        case let .struct(s): return s.name
        case let .choice(c): return c.name
        case let .rawEnum(e): return e.name
        }
    }

    public var kotlinTarget: KotlinTarget {
        switch self {
        case let .struct(s): return s.kotlinTarget
        case let .choice(c): return c.kotlinTarget
        case let .rawEnum(e): return e.kotlinTarget
        }
    }
}

public struct WireStruct: Equatable, Sendable {
    public var name: String
    public var fields: [WireField]
    public var reservedTags: [UInt32]
    public var kotlinTarget: KotlinTarget
    public init(
        name: String,
        fields: [WireField],
        reservedTags: [UInt32] = [],
        kotlinTarget: KotlinTarget,
    ) {
        self.name = name
        self.fields = fields
        self.reservedTags = reservedTags
        self.kotlinTarget = kotlinTarget
    }
}

public struct WireField: Equatable, Sendable {
    public var name: String
    public var typeText: String
    /// For sugared `T?` / `Optional<T>` fields, the inner `T` rendered as
    /// text. For non-optional fields equals `typeText`. Carries the same
    /// distinction the Swift macro uses to drive Optional-aware emission.
    public var wrappedTypeText: String
    public var isOptional: Bool
    /// TLV tag number for this field. Computed by the parser using the
    /// same fill-gaps algorithm as `@WireFormat` macro expansion: explicit
    /// `@WireFormatField(tag:)` wins; otherwise the smallest counter ≥ 1
    /// not already in `reservedTags ∪ explicitTags`.
    public var tag: UInt32
    public init(
        name: String,
        typeText: String,
        wrappedTypeText: String? = nil,
        isOptional: Bool = false,
        tag: UInt32 = 0,
    ) {
        self.name = name
        self.typeText = typeText
        self.wrappedTypeText = wrappedTypeText ?? typeText
        self.isOptional = isOptional
        self.tag = tag
    }
}

public struct WireChoice: Equatable, Sendable {
    public var name: String
    public var cases: [WireChoiceCase]
    public var kotlinTarget: KotlinTarget
    public init(name: String, cases: [WireChoiceCase], kotlinTarget: KotlinTarget) {
        self.name = name
        self.cases = cases
        self.kotlinTarget = kotlinTarget
    }
}

public struct WireChoiceCase: Equatable, Sendable {
    public var name: String
    /// Associated value fields in declaration order. Empty if the case has no payload.
    public var payload: [PayloadField]
    public init(name: String, payload: [PayloadField]) {
        self.name = name
        self.payload = payload
    }
}

public struct PayloadField: Equatable, Sendable {
    /// The associated-value label, or nil when the case has no label.
    public var label: String?
    public var typeText: String
    public init(label: String?, typeText: String) {
        self.label = label
        self.typeText = typeText
    }
}

public struct WireRawEnum: Equatable, Sendable {
    public var name: String
    public var cases: [String]
    public var kotlinTarget: KotlinTarget
    public init(name: String, cases: [String], kotlinTarget: KotlinTarget) {
        self.name = name
        self.cases = cases
        self.kotlinTarget = kotlinTarget
    }
}

/// Per-type Kotlin emission directive. Mirrors the Swift macro argument
/// shape so the parser can lift it straight off the source.
public enum KotlinTarget: Equatable, Sendable {
    case auto
    case skip
    case explicit(String)
}
