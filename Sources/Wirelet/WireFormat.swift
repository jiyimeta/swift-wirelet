import Foundation

/// A type that can serialize itself into a `WireFormatWriter` in this
/// package's canonical TLV (tag/length/value) binary form.
///
/// Conform manually for primitives, or apply `@WireFormat` to a struct to
/// have the macro emit a synthesized conformance whose layout is a
/// length-prefixed body containing one `(tag, payload)` pair per stored
/// property in declaration order (implicit tags 1, 2, 3, ...).
///
/// Conforming types must declare:
/// - `static var wireType: WireType` — the wire-type used when this value
///   appears as a field of an enclosing TLV record.
/// - `encodePayload(into:)` — write the value's *raw payload bytes* (no
///   tag, no length wrapper). The enclosing record / array adds those.
/// - `encode(into:)` — write the value in its top-level form. For
///   primitives this is identical to `encodePayload`; for nested-struct
///   types, the macro-generated implementation wraps the payload in a
///   varint length so the value is self-delimiting.
public protocol WireFormatEncodable {
    static var wireType: WireType { get }
    func encodePayload(into writer: inout WireFormatWriter)
    func encode(into writer: inout WireFormatWriter)
}

/// A type that can be deserialized from a `WireFormatReader` in this
/// package's canonical TLV binary form.
///
/// - `init(decodingPayload:)` — read the *raw payload bytes* of this
///   value from the reader. For length-delimited types the caller is
///   expected to have already entered a `readLengthPrefixed { ... }`
///   slice (so `reader.isAtEnd` bounds the read).
/// - `init(from:)` — read the value in its top-level form. For nested
///   structs this enters the length-prefix and delegates to
///   `init(decodingPayload:)`.
public protocol WireFormatDecodable {
    init(decodingPayload reader: inout WireFormatReader) throws
    init(from reader: inout WireFormatReader) throws
}

// Default implementations bridge the legacy single-method protocol shape
// to the TLV-aware shape. Tasks 2.4 / 2.5 migrate the Enum / Choice macros
// onto the new requirements explicitly; until then they continue to emit
// only the legacy `encode(into:)` / `init(from:)` bodies, and the defaults
// below let those conformances satisfy the protocol.
extension WireFormatEncodable {
    public func encodePayload(into writer: inout WireFormatWriter) {
        encode(into: &writer)
    }
}

extension WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        try self.init(from: &reader)
    }
}

public typealias WireFormat = WireFormatDecodable & WireFormatEncodable

extension WireFormatEncodable {
    /// Convenience: encode the value into a fresh writer and return the bytes.
    public func encodeToData() -> Data {
        var writer = WireFormatWriter()
        encode(into: &writer)
        return writer.data
    }
}

extension WireFormatDecodable {
    /// Convenience: decode the value from a self-contained byte buffer.
    /// Trailing bytes (if any) are tolerated.
    public init(decoding data: Data) throws {
        var reader = WireFormatReader(data: data)
        try self.init(from: &reader)
    }
}

/// The 3-bit wire-type field stored in the low bits of every tag varint.
public enum WireType: UInt8, Sendable {
    case varint = 0          // Int / UInt / Bool / enum raw
    case fixed64 = 1         // Double, fixed Int64
    case lengthDelimited = 2 // String / Data / Array / Dictionary / nested struct / choice
    case fixed32 = 5         // Float, fixed Int32
}

/// Errors thrown while decoding wire-format payloads.
public enum WireFormatError: Error, Equatable {
    /// The reader needed `needed` bytes but only `remaining` were left.
    case truncated(needed: Int, remaining: Int)
    /// A length prefix decoded to a negative value (signed `Int32`).
    case invalidCount(Int32)
    /// String byte payload was not valid UTF-8.
    case invalidUTF8
    /// A tag varint had an unrecognized wire-type code (i.e. not 0/1/2/5).
    case unknownWireType(UInt8)
    /// A varint exceeded the maximum 10 bytes (64-bit value).
    case varintOverflow
    /// An unknown tag was encountered and the decoder is in strict mode.
    /// `wireType` allows the caller to skip the field if they relax.
    case unknownTag(tag: UInt32, wireType: WireType)
    /// `@WireFormatChoice` saw a discriminator outside the known case range.
    case unknownChoiceDiscriminator(UInt32)
}

/// Per-type override controlling how the external Kotlin codec
/// emitter (`emit-wirelet-kotlin`) handles this type. The Swift macro
/// expansion ignores this argument — it's metadata for the external
/// tool only.
///
/// - `.auto`: resolve target Kotlin location via project config
///   (`kotlin-codegen.json`). Default when the argument is omitted.
/// - `.skip`: do not emit a Kotlin codec for this type. Use for types
///   that exist only in Swift-side flows.
/// - `.explicit(String)`: place the Kotlin codec at the given
///   fully-qualified package + class name, ignoring config rules.
public enum KotlinTarget: Sendable {
    case auto
    case skip
    case explicit(String)
}

/// Attach to a `struct` to synthesize a `WireFormat` conformance whose
/// encoding is each stored property in declaration order. All stored
/// property types must themselves conform to `WireFormat`.
///
/// Limitations (experimental scope):
/// - Target must be a `struct`. Classes, enums, actors are rejected with
///   a diagnostic.
/// - Computed properties are ignored. Stored properties with initializers
///   are still encoded — their wire bytes are the runtime value, not the
///   initializer expression.
/// - Property attributes other than access modifiers are not inspected.
@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormat() = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatMacro",
)

@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormat(kotlin: KotlinTarget) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatMacro",
)

/// Variant that declares a list of tag numbers no field of this struct may
/// use. Useful when migrating a wire schema where some legacy tags should
/// not be re-emitted by implicit assignment.
@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormat(reservedTags: [UInt32]) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatMacro",
)

@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormat(reservedTags: [UInt32], kotlin: KotlinTarget) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatMacro",
)

/// Peer macro attached to a stored property inside a `@WireFormat` struct
/// to assign an explicit TLV tag. Properties without this attribute receive
/// implicit tags 1, 2, 3, ... in declaration order, skipping any explicit
/// or reserved tag values.
///
/// Tag value must be > 0 and must not appear in the enclosing
/// `@WireFormat(reservedTags:)` list. Two properties may not share the
/// same explicit tag — either condition is reported as a compile-time
/// error by the enclosing `@WireFormat` macro.
@attached(peer)
public macro WireFormatField(tag: UInt32) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatFieldMacro",
)

/// Attach to a `CaseIterable & Equatable` enum to synthesize a `WireFormat`
/// conformance whose encoding is the case's `allCases` ordinal as a single
/// `UInt8`. Caps at 256 cases.
///
/// Wire-stable as long as the order of cases in the source is preserved.
/// Adding a new case at the end is forward-compatible (old readers will
/// reject it with `invalidCount`); reordering or removing cases is a
/// breaking change to the wire layout.
@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormatEnum() = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatEnumMacro",
)

@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormatEnum(kotlin: KotlinTarget) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatEnumMacro",
)

/// Attach to a sum-type enum (cases with associated values) to synthesize
/// a `WireFormat` conformance whose encoded layout is:
///
/// ```
/// varint discriminator   ← case's declaration-order index (0, 1, 2, …)
/// payload                ← associated values of the selected case, encoded
///                          as WireFormat in declaration order
/// ```
///
/// All associated value types must conform to `WireFormat`. Cases without
/// associated values encode as just the discriminator varint.
///
/// Wire-stable contract: declaration order is the discriminator. Adding
/// a case at the end is forward-compatible (old readers throw
/// `WireFormatError.invalidCount`); reordering/removing cases is a
/// breaking wire change.
@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormatChoice() = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatChoiceMacro",
)

@attached(
    extension,
    conformances: WireFormatEncodable, WireFormatDecodable,
    names: named(wireType), named(encode(into:)), named(encodePayload(into:)),
           named(init(from:)), named(init(decodingPayload:))
)
public macro WireFormatChoice(kotlin: KotlinTarget) = #externalMacro(
    module: "WireletMacros",
    type: "WireFormatChoiceMacro",
)
