// Re-export the C JNI module on Android; on Apple this import is a no-op
// because the macro-generated extensions are themselves guarded by
// `#if os(Android)` and so the JNI types are never referenced.
#if os(Android)
@_exported import SwiftJavaJNICore
#endif

/// Marker for a method that the Wirelet Observable Kotlin codegen should
/// expose on the generated `<Name>ViewModel`. Methods without this
/// attribute are not bridged. The macro itself synthesizes no code.
@attached(peer)
public macro WireletExpose() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletExposeMacro"
)

/// Marker attribute for a `final class` that is also `@Observable` and
/// should be bridged to a Kotlin `ViewModel` via JNI. The macro itself
/// emits no Swift code; the `WireletObservableBridges` SwiftPM build tool
/// plugin scans for this attribute and emits the `@_cdecl` global JNI
/// bridges as a separate generated `.swift` file in the build output.
///
/// Restrictions:
/// - The class must be `final`.
/// - The class must also carry Apple's `@Observable` attribute.
/// - Stored properties must use one of: primitive (`Int8/16/32/64`,
///   `UInt8/16/32/64`, `Bool`, `Float`, `Double`, `String`), `@WireFormat`
///   struct/enum, or `Array<T>` / `Optional<T>` of the above.
/// - `@ObservationIgnored` properties are skipped.
@attached(peer)
public macro WireletObservable() = #externalMacro(
    module: "WireletObservableMacros",
    type: "WireletObservableMacro"
)
