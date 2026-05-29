// Re-export the C JNI module on Android; on Apple this import is a no-op
// because the macro-generated extensions are themselves guarded by
// `#if os(Android)` and so the JNI types are never referenced.
#if os(Android)
@_exported import CWireletJNI
#endif

/// Marker for a method that the Wirelet Observable Kotlin codegen should
/// expose on the generated `<Name>ViewModel`. Methods without this
/// attribute are not bridged. The macro itself synthesizes no code.
@attached(peer)
public macro WireletExpose() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletExposeMacro"
)

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
@attached(peer, names: arbitrary)
public macro WireletObservable() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletObservableMacro"
)
