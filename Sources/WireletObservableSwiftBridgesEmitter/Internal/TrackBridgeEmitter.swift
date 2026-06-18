import WireletObservableSchema

/// Renders the per-property `_track` JNI bridge global function.
enum TrackBridgeEmitter {
    static func render(className: String, property: ObservableProperty) -> String {
        switch property.kind {
        case .primitive:
            return renderPrimitiveBridge(className: className, property: property)
        case .string:
            return renderStringBridge(className: className, property: property)
        case .wireFormat:
            return renderWireFormatBridge(className: className, property: property)
        case .wireFormatArray:
            return renderWireFormatArrayBridge(className: className, property: property)
        case .optionalPrimitive:
            return renderOptionalBridge(className: className, property: property)
        case .optionalString:
            return renderOptionalStringTrackBridge(className: className, property: property)
        case .optionalWireFormat:
            return renderOptionalBridge(className: className, property: property)
        }
    }

    // MARK: - Per-kind renderers

    private static func renderPrimitiveBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        let jniType = primitiveJNIType(property.swiftTypeText)
        let returnExpr: String = {
            switch property.swiftTypeText {
            case "Bool": return "jboolean(snapshot ? 1 : 0)"
            default: return "\(jniType)(snapshot)"
            }
        }()
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> \(jniType) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return \(returnExpr)
        }
        """
    }

    private static func renderStringBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jstring? {
            guard let env, let envValue = env.pointee else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return snapshot.withCString { cstr in
                envValue.pointee.NewStringUTF(env, cstr)
            }
        }
        """
    }

    private static func renderWireFormatBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else {
                return nil
            }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return WireletObservableJNI.encode(snapshot, env: env)
        }
        """
    }

    private static func renderWireFormatArrayBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else {
                return nil
            }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            return WireletObservableJNI.encodeArray(snapshot, env: env)
        }
        """
    }

    private static func renderOptionalBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jbyteArray? {
            guard let env else {
                return nil
            }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            guard let value = snapshot else {
                return nil
            }
            return WireletObservableJNI.encode(value, env: env)
        }
        """
    }

    private static func renderOptionalStringTrackBridge(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
        public func __\(className)_\(property.name)_track_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ on_change: jobject?
        ) -> jstring? {
            guard let env, let envValue = env.pointee else { return nil }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            let runnable = JObject(env: env, jobject: on_change)
            let snapshot = ObservationTrackingHelper.read(\\.\(property.name), on: me) {
                runnable?.call(method: "run")
            }
            guard let value = snapshot else { return nil }
            return value.withCString { cstr in
                envValue.pointee.NewStringUTF(env, cstr)
            }
        }
        """
    }

    // MARK: - Helpers

    private static func primitiveJNIType(_ swiftType: String) -> String {
        switch swiftType {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "jint"
        case "Int64", "UInt32", "UInt64": return "jlong"
        case "Bool": return "jboolean"
        case "Float": return "jfloat"
        case "Double": return "jdouble"
        default: return "jint"
        }
    }
}
