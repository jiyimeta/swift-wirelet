// Re-export the C JNI module on Android; on Apple this import is a no-op
// because the macro-generated extensions are themselves guarded by
// `#if os(Android)` and so the JNI types are never referenced.
#if os(Android)
@_exported import CWireletJNI
#endif

// Macro declarations are added in Task 4 / Task 8.
