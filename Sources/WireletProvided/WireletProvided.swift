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
    type: "WireletProvidedMacro",
)
