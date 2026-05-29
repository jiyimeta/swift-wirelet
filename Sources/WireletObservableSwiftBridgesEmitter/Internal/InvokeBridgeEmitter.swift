import WireletObservableSchema

/// Renders `@WireletExpose` method invoke JNI bridge global functions.
///
/// Accepts any number of arguments whose types classify via
/// `InvokeArgClassifier`. Each arg crosses JNI as its native primitive
/// representation (`jint`, `jboolean`, etc.) or as `jbyteArray?` /
/// `jstring?` for types that need wire-format marshalling — there is no
/// hidden wrapper struct. See
/// `docs/superpowers/plans/2026-05-29-wirelet-observable-multi-arg-methods.md`.
enum InvokeBridgeEmitter {
    static func render(className: String, method: ObservableMethod) -> String? {
        let methodName = method.name
        let params = method.parameters

        if params.isEmpty {
            return renderZeroArg(className: className, methodName: methodName)
        }
        return renderNArg(className: className, methodName: methodName, params: params)
    }

    // MARK: - Zero-arg

    private static func renderZeroArg(className: String, methodName: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(methodName)()
        }
        """
    }

    // MARK: - N-arg

    private static func renderNArg(
        className: String,
        methodName: String,
        params: [ObservableMethodParameter]
    ) -> String {
        let paramList = params.enumerated().map { idx, p in
            "    _ arg\(idx): \(jniParameterType(for: p.typeText))"
        }.joined(separator: ",\n")

        let decodeBlocks = params.enumerated().map { idx, p in
            decodeBlock(idx: idx, param: p)
        }.joined(separator: "\n    ")

        let callArgs = params.enumerated().map { idx, p in
            let value = "decoded\(idx)"
            return p.label == "_" ? value : "\(p.label): \(value)"
        }.joined(separator: ", ")

        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
        \(paramList)
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            \(decodeBlocks)
            me.\(methodName)(\(callArgs))
        }
        """
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
    /// that early-return — so the bridge fails fast on malformed input.
    private static func decodeBlock(idx: Int, param: ObservableMethodParameter) -> String {
        let argName = "arg\(idx)"
        let outName = "decoded\(idx)"
        switch InvokeArgClassifier.classify(param.typeText) {
        case .primitive(_, let swiftCast):
            return "let \(outName) = \(swiftCast)(\(argName))"
        case .bool:
            return "let \(outName) = (\(argName) != 0)"
        case .string:
            return """
            guard let env, let envValue = env.pointee, let raw\(idx) = \(argName) else {
                return
            }
            let cstr\(idx) = envValue.pointee.GetStringUTFChars(env, raw\(idx), nil)
            defer { envValue.pointee.ReleaseStringUTFChars(env, raw\(idx), cstr\(idx)) }
            guard let cstr\(idx) else {
                return
            }
            let \(outName) = String(cString: cstr\(idx))
            """
        case .wireFormat(let typeName):
            return """
            guard let env, let raw\(idx) = \(argName) else {
                return
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            guard let \(outName) = try? \(typeName)(decoding: data\(idx)) else {
                return
            }
            """
        case .optionalPrimitive(let inner):
            return """
            let \(outName): \(inner)?
            if let raw\(idx) = \(argName), let env {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(inner)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .optionalString:
            return """
            let \(outName): String?
            if let raw\(idx) = \(argName), let env, let envValue = env.pointee {
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
            if let raw\(idx) = \(argName), let env {
                let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
                \(outName) = try? \(typeName)(decoding: data\(idx))
            } else {
                \(outName) = nil
            }
            """
        case .array(let elementTypeName):
            return """
            guard let env, let raw\(idx) = \(argName) else {
                return
            }
            let data\(idx) = WireletObservableJNI.dataFromByteArray(raw\(idx), env: env)
            var reader\(idx) = WireFormatReader(data: data\(idx))
            guard let count\(idx) = try? reader\(idx).readVarint() else {
                return
            }
            var elements\(idx): [\(elementTypeName)] = []
            elements\(idx).reserveCapacity(Int(count\(idx)))
            for _ in 0..<Int(count\(idx)) {
                guard let element\(idx) = try? \(elementTypeName)(from: &reader\(idx)) else {
                    return
                }
                elements\(idx).append(element\(idx))
            }
            let \(outName) = elements\(idx)
            """
        }
    }
}
