import WireletObservableSchema

/// Renders the constructor (`_new`) and destructor (`_release`) JNI bridges.
enum ConstructorEmitter {
    static func renderConstructor(
        className: String,
        initParameters: [ObservableInitParameter]
    ) -> String {
        guard !initParameters.isEmpty else {
            // No-arg path — backward compatible, byte-for-byte unchanged.
            return """
            @_cdecl("WireletObservable_\(className)_new")
            public func __\(className)_new_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
                _ this_or_class: jobject?
            ) -> jlong {
                return WireletObservableJNI.retain(\(className)())
            }
            """
        }

        // Injected path: one `jobject?` adapter per init parameter, each
        // wrapped into its `<Type>WireletProxy` (Phase 2) before construction.
        let argParams = initParameters.enumerated()
            .map { idx, _ in "    _ arg\(idx): jobject?" }
            .joined(separator: ",\n")
        let guards = initParameters.enumerated()
            .map { idx, _ in
                "    guard let obj\(idx) = JObject(env: env, jobject: arg\(idx)) else { return 0 }"
            }
            .joined(separator: "\n")
        let callArgs = initParameters.enumerated()
            .map { idx, param -> String in
                let value = "\(param.typeText)WireletProxy(adapter: obj\(idx))"
                return param.label == "_" ? value : "\(param.label): \(value)"
            }
            .joined(separator: ", ")

        return """
        @_cdecl("WireletObservable_\(className)_new")
        public func __\(className)_new_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
        \(argParams)
        ) -> jlong {
            guard let env else { return 0 }
        \(guards)
            return WireletObservableJNI.retain(\(className)(\(callArgs)))
        }
        """
    }

    static func renderDestructor(className: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_release")
        public func __\(className)_release_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong
        ) {
            WireletObservableJNI.release(self_ptr, as: \(className).self)
        }
        """
    }
}
