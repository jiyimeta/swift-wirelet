import WireletObservableSchema

/// Renders `@WireletExpose` method invoke JNI bridge global functions.
enum InvokeBridgeEmitter {
    /// Returns the rendered bridge string, or `nil` if the method signature is
    /// unsupported (more than one arg, or a primitive/String arg). The CLI can
    /// choose to warn or skip — here we silently skip, matching how the schema
    /// layer behaves.
    static func render(className: String, method: ObservableMethod) -> String? {
        let methodName = method.name
        let params = method.parameters

        if params.isEmpty {
            return renderZeroArg(className: className, methodName: methodName)
        }

        if params.count == 1, let param = params.first {
            let argType = param.typeText
            // Primitive types and String are not supported in Phase 1.
            if isPrimitiveType(argType) || argType == "String" {
                return nil
            }
            return renderOneArg(className: className, methodName: methodName, param: param)
        }

        // More than one arg — unsupported in Phase 1.
        return nil
    }

    // MARK: - Per-shape renderers

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

    private static func renderOneArg(
        className: String,
        methodName: String,
        param: ObservableMethodParameter
    ) -> String {
        let argLabel = param.label
        let argType = param.typeText
        let callSite = argLabel == "_" ? "decoded" : "\(argLabel): decoded"
        return """
        @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
        public func __\(className)_\(methodName)_invoke_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ arg0: jbyteArray?
        ) {
            guard let env, let arg0 else { return }
            let data = WireletObservableJNI.dataFromByteArray(arg0, env: env)
            guard let decoded = try? \(argType)(decoding: data) else { return }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(methodName)(\(callSite))
        }
        """
    }

    // MARK: - Helpers

    private static func isPrimitiveType(_ typeText: String) -> Bool {
        switch typeText {
        case "Int8", "Int16", "Int32", "Int64",
             "UInt8", "UInt16", "UInt32", "UInt64",
             "Bool", "Float", "Double":
            return true
        default:
            return false
        }
    }
}
