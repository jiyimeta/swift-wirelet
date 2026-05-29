/// Renders the constructor (`_new`) and destructor (`_release`) JNI bridges.
enum ConstructorEmitter {
    static func renderConstructor(className: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_new")
        public func __\(className)_new_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?
        ) -> jlong {
            return WireletObservableJNI.retain(\(className)())
        }
        """
    }

    static func renderDestructor(className: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_release")
        public func __\(className)_release_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ self_ptr: jlong
        ) {
            WireletObservableJNI.release(self_ptr, as: \(className).self)
        }
        """
    }
}
