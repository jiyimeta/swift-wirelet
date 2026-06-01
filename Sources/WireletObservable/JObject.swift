#if os(Android)
import CWireletJNI
import Foundation

/// Wraps a JNI `jobject` so Swift can invoke its methods without spelling
/// out the JNI ceremony. Holds a JNI **global reference** (the local ref
/// passed across an `@_cdecl` boundary would be invalid by the time a
/// later call fires) and the `JavaVM` so calls can `AttachCurrentThread`
/// from whatever thread mutates Swift state.
///
/// Originally introduced for the `@WireletObservable` re-arm path (a single
/// `Runnable.run()` call); generalized here to typed, argument-bearing
/// calls so Swift can drive a Kotlin-implemented service (`@WireletProvided`).
public final class JObject: @unchecked Sendable {
    /// A value to pass as a JNI method argument. Object-typed cases
    /// (`bytes`, `string`) allocate a local ref that the call frees.
    public enum Arg {
        case int(Int32)
        case long(Int64)
        case bool(Bool)
        case float(Float)
        case double(Double)
        case bytes([UInt8])   // -> jbyteArray ([B)
        case string(String)   // -> jstring (Ljava/lang/String;)
    }

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

    /// Convenience for the observable re-arm path: `void <name>()`.
    public func call(method name: String) {
        callVoid(method: name, signature: "()V")
    }

    public func callVoid(method: String, signature: String, _ args: [Arg] = []) {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            envValue.pointee.CallVoidMethodA(env, globalRef, mid, jargs)
            return ()
        }
    }

    public func callInt(method: String, signature: String, _ args: [Arg] = []) -> Int32? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            Int32(envValue.pointee.CallIntMethodA(env, globalRef, mid, jargs))
        }
    }

    public func callBool(method: String, signature: String, _ args: [Arg] = []) -> Bool? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs in
            envValue.pointee.CallBooleanMethodA(env, globalRef, mid, jargs) != 0
        }
    }

    /// Calls a method whose JNI return type is `[B` (a byte array) and
    /// copies the bytes out. Returns `nil` if the Kotlin method returned
    /// `null` or the call failed.
    public func callBytes(method: String, signature: String, _ args: [Arg] = []) -> [UInt8]? {
        perform(method: method, signature: signature, args: args) { env, envValue, mid, jargs -> [UInt8]? in
            guard let arr = envValue.pointee.CallObjectMethodA(env, globalRef, mid, jargs) else {
                return nil
            }
            let len = envValue.pointee.GetArrayLength(env, arr)
            guard len > 0 else { return [] }
            var buffer = [UInt8](repeating: 0, count: Int(len))
            buffer.withUnsafeMutableBytes { raw in
                envValue.pointee.GetByteArrayRegion(
                    env, arr, 0, len,
                    raw.baseAddress?.assumingMemoryBound(to: jbyte.self)
                )
            }
            envValue.pointee.DeleteLocalRef(env, arr)
            return buffer
        } ?? nil
    }

    // MARK: - Core

    /// Attaches the current thread, resolves the method, marshals `args`
    /// into a `jvalue` array (freeing object local refs afterwards),
    /// invokes `body`, and clears any pending Java exception.
    private func perform<R>(
        method: String,
        signature: String,
        args: [Arg],
        _ body: (UnsafeMutablePointer<JNIEnv?>, JNIEnv, jmethodID, UnsafeMutablePointer<jvalue>?) -> R
    ) -> R? {
        var env: UnsafeMutablePointer<JNIEnv?>?
        let attachResult = vm.pointee?.pointee.AttachCurrentThread(vm, &env, nil) ?? JNI_ERR
        guard attachResult == JNI_OK, let env, let envValue = env.pointee else { return nil }
        guard let cls = envValue.pointee.GetObjectClass(env, globalRef) else { return nil }
        guard let mid = envValue.pointee.GetMethodID(env, cls, method, signature) else { return nil }

        var jargs: [jvalue] = []
        var localRefs: [jobject] = []
        jargs.reserveCapacity(args.count)
        for arg in args {
            switch arg {
            case .int(let v): jargs.append(jvalue(i: jint(v)))
            case .long(let v): jargs.append(jvalue(j: jlong(v)))
            case .bool(let v): jargs.append(jvalue(z: jboolean(v ? JNI_TRUE : JNI_FALSE)))
            case .float(let v): jargs.append(jvalue(f: jfloat(v)))
            case .double(let v): jargs.append(jvalue(d: jdouble(v)))
            case .bytes(let bytes):
                guard let arr = envValue.pointee.NewByteArray(env, jsize(bytes.count)) else { return nil }
                if !bytes.isEmpty {
                    bytes.withUnsafeBufferPointer { bp in
                        bp.baseAddress!.withMemoryRebound(to: jbyte.self, capacity: bytes.count) { jb in
                            envValue.pointee.SetByteArrayRegion(env, arr, 0, jsize(bytes.count), jb)
                        }
                    }
                }
                localRefs.append(arr)
                jargs.append(jvalue(l: arr))
            case .string(let s):
                guard let js = s.withCString({ envValue.pointee.NewStringUTF(env, $0) }) else { return nil }
                localRefs.append(js)
                jargs.append(jvalue(l: js))
            }
        }
        defer { for ref in localRefs { envValue.pointee.DeleteLocalRef(env, ref) } }

        let result = jargs.withUnsafeMutableBufferPointer { buf in
            body(env, envValue, mid, buf.baseAddress)
        }
        if envValue.pointee.ExceptionCheck(env) != 0 {
            envValue.pointee.ExceptionDescribe(env)
            envValue.pointee.ExceptionClear(env)
        }
        return result
    }
}
#endif
