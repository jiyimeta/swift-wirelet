import WireletObservableSchema

/// Renders `@WireletExpose` method invoke JNI bridge global functions.
///
/// Accepts any number of arguments whose types classify via
/// `InvokeArgClassifier`. Each arg crosses JNI as its native primitive
/// representation (`jint`, `jboolean`, etc.) or as `jbyteArray?` /
/// `jstring?` for types that need wire-format marshalling — there is no
/// hidden wrapper struct. A non-`Void` return is marshalled back the same
/// way (primitive directly, `String` via `NewStringUTF`, `@WireFormat` /
/// `[@WireFormat]` via `WireletObservableJNI.encode`/`encodeArray`). See
/// `docs/superpowers/plans/2026-05-29-wirelet-observable-multi-arg-methods.md`.
enum InvokeBridgeEmitter {
    static func render(className: String, method: ObservableMethod) -> String? {
        let ret = returnInfo(method.returnTypeText)
        if method.parameters.isEmpty {
            return renderZeroArg(className: className, methodName: method.name, ret: ret)
        }
        return renderNArg(className: className, methodName: method.name, params: method.parameters, ret: ret)
    }

    // MARK: - Return marshalling

    /// How an exposed method's return value crosses JNI back to Kotlin.
    private struct ReturnInfo {
        /// JNI return-type clause, e.g. `" -> jstring?"`. `""` for a `Void` return.
        let signature: String
        /// Statement used by every early-return guard (env unwrap, decode failure): `return` for `Void`,
        /// `return nil` for object returns (`jstring?`/`jbyteArray?`), `return 0` for primitive returns.
        let earlyReturn: String
        /// Whether the return marshalling dereferences `env`.
        let needsEnv: Bool
        /// Whether the return marshalling needs `env.pointee` (String → `NewStringUTF`).
        let needsEnvValue: Bool
        /// Renders the trailing body statement(s) from the call expression (`me.foo(args)`).
        let renderTail: (String) -> String
    }

    private static func returnInfo(_ returnTypeText: String?) -> ReturnInfo {
        guard let returnTypeText else {
            return ReturnInfo(
                signature: "", earlyReturn: "return", needsEnv: false, needsEnvValue: false,
                renderTail: { $0 }
            )
        }
        switch InvokeArgClassifier.classify(returnTypeText) {
        case .primitive(let jniType, _):
            return ReturnInfo(
                signature: " -> \(jniType)", earlyReturn: "return 0", needsEnv: false, needsEnvValue: false,
                renderTail: { "return \(jniType)(\($0))" }
            )
        case .bool:
            return ReturnInfo(
                signature: " -> jboolean", earlyReturn: "return 0", needsEnv: false, needsEnvValue: false,
                renderTail: { "return (\($0)) ? 1 : 0" }
            )
        case .string:
            return ReturnInfo(
                signature: " -> jstring?", earlyReturn: "return nil", needsEnv: true, needsEnvValue: true,
                renderTail: { "let __result = \($0)\n    return __result.withCString { envValue.pointee.NewStringUTF(env, $0) }" }
            )
        case .wireFormat:
            return ReturnInfo(
                signature: " -> jbyteArray?", earlyReturn: "return nil", needsEnv: true, needsEnvValue: false,
                renderTail: { "return WireletObservableJNI.encode(\($0), env: env)" }
            )
        case .array:
            return ReturnInfo(
                signature: " -> jbyteArray?", earlyReturn: "return nil", needsEnv: true, needsEnvValue: false,
                renderTail: { "return WireletObservableJNI.encodeArray(\($0), env: env)" }
            )
        case .optionalString, .optionalPrimitive, .optionalWireFormat:
            // Optional returns are not supported yet; fail the build loudly rather than drop the value.
            return ReturnInfo(
                signature: " -> jbyteArray?", earlyReturn: "return nil", needsEnv: false, needsEnvValue: false,
                renderTail: { _ in
                    #"#error("wirelet: @WireletExpose optional return type '\#(returnTypeText)' is not supported")"#
                }
            )
        }
    }

    // MARK: - Zero-arg

    private static func renderZeroArg(className: String, methodName: String, ret: ReturnInfo) -> String {
        let call = "me.\(methodName)()"
        let preamble = envPreamble(needsEnvValue: ret.needsEnvValue, needsEnv: ret.needsEnv, earlyReturn: ret.earlyReturn)
        let body = preamble.isEmpty ? ret.renderTail(call) : "\(preamble)\n    \(ret.renderTail(call))"
        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong
        )\(ret.signature) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            \(body)
        }
        """
    }

    // MARK: - N-arg

    private static func renderNArg(
        className: String,
        methodName: String,
        params: [ObservableMethodParameter],
        ret: ReturnInfo
    ) -> String {
        let paramList = params.enumerated().map { idx, p in
            "    _ arg\(idx): \(jniParameterType(for: p.typeText))"
        }.joined(separator: ",\n")

        // Unwrap `env` (and `env.pointee`) ONCE for the whole method. The JNI
        // parameter `env` is optional, so binding it with `guard let env` inside
        // each per-arg decode block would shadow it as non-optional for the
        // remaining args — the second `guard let env` then fails to compile.
        // Hoisting the unwrap here keeps `env`/`envValue` non-optional and in
        // scope for every decode block AND the return marshalling.
        let needsEnvValue = ret.needsEnvValue || params.contains { usesEnvValue($0.typeText) }
        let needsEnv = ret.needsEnv || params.contains { usesEnv($0.typeText) }
        let envPre = envPreamble(needsEnvValue: needsEnvValue, needsEnv: needsEnv, earlyReturn: ret.earlyReturn)

        let decodeBlocks = params.enumerated().map { idx, p in
            decodeBlock(idx: idx, param: p, earlyReturn: ret.earlyReturn)
        }.joined(separator: "\n    ")

        let callArgs = params.enumerated().map { idx, p in
            let value = "decoded\(idx)"
            return p.label == "_" ? value : "\(p.label): \(value)"
        }.joined(separator: ", ")
        let call = "me.\(methodName)(\(callArgs))"

        let preamble = envPre.isEmpty ? "" : "\(envPre)\n    "

        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
        \(paramList)
        )\(ret.signature) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            \(preamble)\(decodeBlocks)
            \(ret.renderTail(call))
        }
        """
    }

    /// A single `guard` that unwraps `env` (and `envValue` when a String is
    /// marshalled either way) for the whole method, or `""` when neither the
    /// arguments nor the return touch the JNI environment (all primitives /
    /// bools). The guard's early-return matches the method's return type.
    private static func envPreamble(needsEnvValue: Bool, needsEnv: Bool, earlyReturn: String) -> String {
        if needsEnvValue {
            return """
            guard let env, let envValue = env.pointee else {
                \(earlyReturn)
            }
            """
        }
        if needsEnv {
            return """
            guard let env else {
                \(earlyReturn)
            }
            """
        }
        return ""
    }

    /// Whether the argument's decode block dereferences `env` at all.
    private static func usesEnv(_ typeText: String) -> Bool {
        switch InvokeArgClassifier.classify(typeText) {
        case .primitive, .bool: return false
        default: return true
        }
    }

    /// Whether the argument's decode block needs `env.pointee` (String marshalling).
    private static func usesEnvValue(_ typeText: String) -> Bool {
        switch InvokeArgClassifier.classify(typeText) {
        case .string, .optionalString: return true
        default: return false
        }
    }

    // MARK: - Per-arg JNI parameter type

    private static func jniParameterType(for typeText: String) -> String {
        switch InvokeArgClassifier.classify(typeText) {
        case .primitive(let jniSwiftType, _): return jniSwiftType
        case .bool:                           return "jboolean"
        case .string, .optionalString:        return "jstring?"
        case .wireFormat,
             .optionalPrimitive,
             .optionalWireFormat,
             .array:
            return "jbyteArray?"
        }
    }

    // MARK: - Per-arg decode block

    /// Returns a Swift statement that defines `decoded<idx>` from `arg<idx>`.
    /// For types that can fail decoding, the statement embeds `guard` clauses
    /// that early-return `earlyReturn` — so the bridge fails fast on malformed
    /// input with a value matching the method's JNI return type.
    ///
    /// `env` and (for String marshalling) `envValue` are unwrapped once by the
    /// method-level preamble (see `envPreamble`); these blocks reuse the
    /// non-optional bindings rather than re-binding them per argument.
    private static func decodeBlock(idx: Int, param: ObservableMethodParameter, earlyReturn: String) -> String {
        let argName = "arg\(idx)"
        let outName = "decoded\(idx)"
        switch InvokeArgClassifier.classify(param.typeText) {
        case .primitive(_, let swiftCast):
            return "let \(outName) = \(swiftCast)(\(argName))"
        case .bool:
            return "let \(outName) = (\(argName) != 0)"
        case .string:
            return """
            guard let raw\(idx) = \(argName) else {
                \(earlyReturn)
            }
            let cstr\(idx) = envValue.pointee.GetStringUTFChars(env, raw\(idx), nil)
            defer { envValue.pointee.ReleaseStringUTFChars(env, raw\(idx), cstr\(idx)) }
            guard let cstr\(idx) else {
                \(earlyReturn)
            }
            let \(outName) = String(cString: cstr\(idx))
            """
        case .wireFormat(let typeName):
            return """
            guard let raw\(idx) = \(argName) else {
                \(earlyReturn)
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            guard let \(outName) = try? \(typeName)(decoding: data\(idx)) else {
                \(earlyReturn)
            }
            """
        case .optionalPrimitive(let inner):
            return """
            let \(outName): \(inner)?
            if let raw\(idx) = \(argName) {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(inner)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .optionalString:
            return """
            let \(outName): String?
            if let raw\(idx) = \(argName) {
                let cstr\(idx) = envValue.pointee.GetStringUTFChars(env, raw\(idx), nil)
                defer { envValue.pointee.ReleaseStringUTFChars(env, raw\(idx), cstr\(idx)) }
                \(outName) = cstr\(idx).map { String(cString: $0) }
            } else {
                \(outName) = nil
            }
            """
        case .optionalWireFormat(let typeName):
            return """
            let \(outName): \(typeName)?
            if let raw\(idx) = \(argName) {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(typeName)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .array(let elementTypeName):
            return """
            guard let raw\(idx) = \(argName) else {
                \(earlyReturn)
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            var reader\(idx) = WireFormatReader(data: data\(idx))
            guard let count\(idx) = try? reader\(idx).readVarint() else {
                \(earlyReturn)
            }
            var elements\(idx): [\(elementTypeName)] = []
            elements\(idx).reserveCapacity(Int(count\(idx)))
            for _ in 0..<Int(count\(idx)) {
                guard let element\(idx) = try? \(elementTypeName)(from: &reader\(idx)) else {
                    \(earlyReturn)
                }
                elements\(idx).append(element\(idx))
            }
            let \(outName) = elements\(idx)
            """
        }
    }
}
