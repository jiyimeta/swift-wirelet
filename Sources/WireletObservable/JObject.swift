#if os(Android)
import CWireletJNI

/// Wraps a JNI `jobject` (specifically, a `java.lang.Runnable`) so the
/// macro-generated `withObservationTracking { … } onChange:` block can
/// invoke `.run()` without spelling out the JNI ceremony.
///
/// Holds a JNI global reference; the local reference passed across the
/// `@_cdecl` boundary would be invalid by the time `onChange` fires.
public final class JObject: @unchecked Sendable {
    // JNI global refs and the JavaVM pointer are designed for cross-thread
    // use via AttachCurrentThread; the wrapper is safe to capture in a
    // @Sendable closure (the macro-generated onChange callbacks).
    private let vm: UnsafeMutablePointer<JavaVM?>
    private let globalRef: jobject

    public init?(env: UnsafeMutablePointer<JNIEnv?>?, jobject local: jobject?) {
        guard let env = env, let envValue = env.pointee, let local = local else {
            return nil
        }
        var rawVM: UnsafeMutablePointer<JavaVM?>?
        let vmResult = envValue.pointee.GetJavaVM(env, &rawVM)
        guard vmResult == JNI_OK, let rawVM else { return nil }
        guard let global = envValue.pointee.NewGlobalRef(env, local) else {
            return nil
        }
        self.vm = rawVM
        self.globalRef = global
    }

    deinit {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return }
        envValue.pointee.DeleteGlobalRef(env, globalRef)
    }

    /// Invokes `Runnable.run()` on the wrapped object. Errors are swallowed
    /// (logged via `__android_log_write` in a future iteration); the macro
    /// generated re-arm path treats `onChange` as best-effort.
    public func call(method name: String) {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return }
        guard let cls = envValue.pointee.GetObjectClass(env, globalRef) else { return }
        guard let methodID = envValue.pointee.GetMethodID(env, cls, name, "()V") else { return }
        // CallVoidMethod is variadic in C; Swift imports it as an
        // OpaquePointer. Use the `A`-suffixed variant which takes a
        // jvalue array (nil for zero-arg methods like Runnable.run()).
        envValue.pointee.CallVoidMethodA(env, globalRef, methodID, nil)
    }
}
#endif
