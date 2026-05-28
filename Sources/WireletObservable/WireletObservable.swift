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
