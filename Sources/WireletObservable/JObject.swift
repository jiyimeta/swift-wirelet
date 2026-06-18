#if os(Android)
    import Foundation
    import SwiftJavaJNICore

    /// Wraps a JNI `jobject` so Swift can invoke its methods without spelling
    /// out the JNI ceremony. Holds a JNI **global reference** (the local ref
    /// passed across an `@_cdecl` boundary would be invalid by the time a
    /// later call fires) plus the shared ``JavaVirtualMachine`` so calls can
    /// re-attach from whatever thread mutates Swift state.
    ///
    /// Originally introduced for the `@WireletObservable` re-arm path (a single
    /// `Runnable.run()` call); generalized here to typed, argument-bearing
    /// calls so Swift can drive a Kotlin-implemented service (`@WireletProvided`).
    ///
    /// PoC note: the JavaVM caching, thread attach/detach, and local-reference
    /// frame bookkeeping are delegated to Apple's `swift-java-jni-core`
    /// (`JavaVirtualMachine` + the `JNIEnvironment` extensions). What remains
    /// here is the dynamic, name+signature method dispatch that jni-core does
    /// not provide (it expects generated bindings instead).
    public final class JObject: @unchecked Sendable {
        /// A value to pass as a JNI method argument. Object-typed cases
        /// (`bytes`, `string`) allocate a local ref freed by the enclosing
        /// local-reference frame.
        public enum Arg {
            case int(Int32)
            case long(Int64)
            case bool(Bool)
            case float(Float)
            case double(Double)
            case bytes([UInt8]) // -> jbyteArray ([B)
            case string(String) // -> jstring (Ljava/lang/String;)
        }

        private let vm: JavaVirtualMachine
        private let globalRef: jobject

        public init?(env: JNIEnvironment?, jobject local: jobject?) {
            guard let env, let local else { return nil }
            // Adopt the already-running ART VM. On Android `shared()` resolves it
            // via `JNI_GetCreatedJavaVMs` (or the instance a generated
            // `JNI_OnLoad` registered with `setShared`).
            guard let vm = try? JavaVirtualMachine.shared() else { return nil }
            guard let global = env.interface.NewGlobalRef(env, local) else {
                return nil
            }
            self.vm = vm
            globalRef = global
        }

        deinit {
            guard let env = try? vm.environment() else { return }
            env.interface.DeleteGlobalRef(env, globalRef)
        }

        /// Convenience for the observable re-arm path: `void <name>()`.
        public func call(method name: String) {
            callVoid(method: name, signature: "()V")
        }

        public func callVoid(method: String, signature: String, _ args: [Arg] = []) {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                env.interface.CallVoidMethodA(env, globalRef, mid, jargs)
                return ()
            }
        }

        public func callInt(method: String, signature: String, _ args: [Arg] = []) -> Int32? {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                Int32(env.interface.CallIntMethodA(env, globalRef, mid, jargs))
            }
        }

        public func callBool(method: String, signature: String, _ args: [Arg] = []) -> Bool? {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                env.interface.CallBooleanMethodA(env, globalRef, mid, jargs) != 0
            }
        }

        public func callLong(method: String, signature: String, _ args: [Arg] = []) -> Int64? {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                Int64(env.interface.CallLongMethodA(env, globalRef, mid, jargs))
            }
        }

        public func callFloat(method: String, signature: String, _ args: [Arg] = []) -> Float? {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                Float(env.interface.CallFloatMethodA(env, globalRef, mid, jargs))
            }
        }

        public func callDouble(method: String, signature: String, _ args: [Arg] = []) -> Double? {
            perform(method: method, signature: signature, args: args) { env, mid, jargs in
                Double(env.interface.CallDoubleMethodA(env, globalRef, mid, jargs))
            }
        }

        /// Calls a method whose JNI return type is `[B` (a byte array) and
        /// copies the bytes out. Returns `nil` if the Kotlin method returned
        /// `null` or the call failed.
        public func callBytes(method: String, signature: String, _ args: [Arg] = []) -> [UInt8]? {
            let result = perform(method: method, signature: signature, args: args) { env, mid, jargs -> [UInt8]? in
                guard let arr = env.interface.CallObjectMethodA(env, globalRef, mid, jargs) else {
                    return nil
                }
                // `arr` is a local ref freed when `perform`'s local frame pops;
                // the bytes are copied out before that happens.
                let len = env.interface.GetArrayLength(env, arr)
                guard len > 0 else { return [] }
                var buffer = [UInt8](repeating: 0, count: Int(len))
                buffer.withUnsafeMutableBytes { raw in
                    env.interface.GetByteArrayRegion(
                        env, arr, 0, len,
                        raw.baseAddress?.assumingMemoryBound(to: jbyte.self),
                    )
                }
                return buffer
            }
            // Flatten `[UInt8]??` into one `nil`: the outer nil is an
            // attach/resolve failure, the inner nil is Kotlin returning null.
            return result.flatMap(\.self)
        }

        /// Calls a method whose JNI return type is `Ljava/lang/String;` and
        /// copies the UTF-8 contents out. Returns `nil` if the Kotlin method
        /// returned `null` or the call failed.
        public func callString(method: String, signature: String, _ args: [Arg] = []) -> String? {
            let result = perform(method: method, signature: signature, args: args) { env, mid, jargs -> String? in
                guard let obj = env.interface.CallObjectMethodA(env, globalRef, mid, jargs) else {
                    return nil
                }
                let cstr = env.interface.GetStringUTFChars(env, obj, nil)
                defer {
                    if let cstr { env.interface.ReleaseStringUTFChars(env, obj, cstr) }
                }
                guard let cstr else { return nil }
                return String(cString: cstr)
            }
            // Flatten `String??` into one `nil`, mirroring callBytes.
            return result.flatMap(\.self)
        }

        // MARK: - Core

        /// Drains (describes + clears) any pending Java exception on `env`.
        /// Returns `true` if an exception was pending. JNI forbids calling most
        /// functions with a pending exception, so this must run before any
        /// follow-up JNI call on the same thread.
        @discardableResult
        private func drainException(_ env: JNIEnvironment) -> Bool {
            guard env.interface.ExceptionCheck(env) != 0 else { return false }
            env.interface.ExceptionDescribe(env)
            env.interface.ExceptionClear(env)
            return true
        }

        /// Attaches the current thread (via the shared VM), resolves the method,
        /// marshals `args` into a `jvalue` array inside a JNI local-reference
        /// frame (which frees object arg refs and the resolved `jclass` on
        /// return), invokes `body`, and drains any pending Java exception so a
        /// later call on this thread starts clean.
        private func perform<R>(
            method: String,
            signature: String,
            args: [Arg],
            _ body: (JNIEnvironment, jmethodID, UnsafeMutablePointer<jvalue>?) -> R,
        ) -> R? {
            guard let env = try? vm.environment() else { return nil }
            let framed: R?? = try? env.withLocalFrame(capacity: max(16, args.count + 4)) { () -> R? in
                guard let cls = env.interface.GetObjectClass(env, globalRef) else {
                    drainException(env)
                    return nil
                }
                guard let mid = env.interface.GetMethodID(env, cls, method, signature) else {
                    drainException(env)
                    return nil
                }

                guard var jargs = marshalArgs(args, into: env) else { return nil }

                let result = jargs.withUnsafeMutableBufferPointer { buf in
                    body(env, mid, buf.baseAddress)
                }
                drainException(env)
                return result
            }
            // `framed` is `R??`: outer nil = withLocalFrame threw (OOM pushing the
            // frame), inner nil = a resolve/marshal step bailed.
            return framed.flatMap(\.self)
        }

        /// Marshals `args` into a `jvalue` array, allocating object-arg local refs
        /// (byte arrays, strings) inside the caller's local-reference frame so they
        /// are freed when that frame pops. Returns `nil` if any JNI allocation
        /// failed or a marshaling step (e.g. `SetByteArrayRegion`) raised a Java
        /// exception, having drained it so the caller starts clean.
        private func marshalArgs(_ args: [Arg], into env: JNIEnvironment) -> [jvalue]? {
            var jargs: [jvalue] = []
            jargs.reserveCapacity(args.count)
            for arg in args {
                switch arg {
                case let .int(v): jargs.append(jvalue(i: jint(v)))
                case let .long(v): jargs.append(jvalue(j: jlong(v)))
                case let .bool(v): jargs.append(jvalue(z: jboolean(v ? JNI_TRUE : JNI_FALSE)))
                case let .float(v): jargs.append(jvalue(f: jfloat(v)))
                case let .double(v): jargs.append(jvalue(d: jdouble(v)))
                case let .bytes(bytes):
                    guard let arr = env.interface.NewByteArray(env, jsize(bytes.count)) else {
                        drainException(env)
                        return nil
                    }
                    if !bytes.isEmpty {
                        bytes.withUnsafeBufferPointer { bp in
                            guard let base = bp.baseAddress else { return }
                            base.withMemoryRebound(to: jbyte.self, capacity: bytes.count) { jb in
                                env.interface.SetByteArrayRegion(env, arr, 0, jsize(bytes.count), jb)
                            }
                        }
                    }
                    jargs.append(jvalue(l: arr)) // freed when the local frame pops
                case let .string(s):
                    guard let js = s.withCString({ env.interface.NewStringUTF(env, $0) }) else {
                        drainException(env)
                        return nil
                    }
                    jargs.append(jvalue(l: js)) // freed when the local frame pops
                }
            }

            // A marshaling step (e.g. SetByteArrayRegion) may have raised
            // without returning nil; bail before issuing the call rather than
            // invoke JNI with an exception pending.
            if drainException(env) {
                return nil
            }
            return jargs
        }
    }
#endif
