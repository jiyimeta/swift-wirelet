import WireletObservableSchema

/// Renders per-property `_set` JNI bridge global functions (mutable properties only).
enum SetterBridgeEmitter {
    static func render(className: String, property: ObservableProperty) -> String {
        switch property.kind {
        case .primitive:
            return renderPrimitiveSetter(className: className, property: property)
        case .string:
            return renderStringSetter(className: className, property: property)
        case let .wireFormat(typeName):
            return renderWireFormatSetter(className: className, property: property, typeName: typeName)
        case let .wireFormatArray(elementTypeName):
            return renderWireFormatArraySetter(
                className: className,
                property: property,
                elementTypeName: elementTypeName,
            )
        case .optionalPrimitive:
            return renderOptionalPrimitiveSetter(className: className, property: property)
        case .optionalString:
            return renderOptionalStringSetter(className: className, property: property)
        case let .optionalWireFormat(typeName):
            return renderOptionalWireFormatSetter(
                className: className,
                property: property,
                typeName: typeName,
            )
        }
    }

    // MARK: - Per-kind renderers

    private static func renderPrimitiveSetter(
        className: String,
        property: ObservableProperty,
    ) -> String {
        let jniType = primitiveJNIType(property.swiftTypeText)
        let assignBody: String = {
            switch property.swiftTypeText {
            case "Bool": return "me.\(property.name) = (new_value != 0)"
            default: return "me.\(property.name) = \(property.swiftTypeText)(new_value)"
            }
        }()
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: \(jniType)
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            \(assignBody)
        }
        """
    }

    private static func renderStringSetter(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jstring?
        ) {
            guard let env, let envValue = env.pointee, let new_value else { return }
            let cstr = envValue.pointee.GetStringUTFChars(env, new_value, nil)
            defer { envValue.pointee.ReleaseStringUTFChars(env, new_value, cstr) }
            guard let cstr else { return }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(property.name) = String(cString: cstr)
        }
        """
    }

    private static func renderWireFormatSetter(
        className: String,
        property: ObservableProperty,
        typeName: String,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jbyteArray?
        ) {
            guard let env, let new_value else { return }
            let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
            guard let decoded = try? \(typeName)(decoding: data) else { return }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(property.name) = decoded
        }
        """
    }

    private static func renderWireFormatArraySetter(
        className: String,
        property: ObservableProperty,
        elementTypeName: String,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jbyteArray?
        ) {
            guard let env, let new_value else { return }
            let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
            var reader = WireFormatReader(data: data)
            guard let count = try? reader.readVarint() else { return }
            var elements: [\(elementTypeName)] = []
            elements.reserveCapacity(Int(count))
            for _ in 0..<Int(count) {
                guard let element = try? \(elementTypeName)(from: &reader) else { return }
                elements.append(element)
            }
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            me.\(property.name) = elements
        }
        """
    }

    private static func renderOptionalPrimitiveSetter(
        className: String,
        property: ObservableProperty,
    ) -> String {
        // Strip the trailing "?" to get the inner type name.
        let innerType = property.swiftTypeText.hasSuffix("?")
            ? String(property.swiftTypeText.dropLast())
            : property.swiftTypeText
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jbyteArray?
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            guard let env, let new_value else {
                me.\(property.name) = nil
                return
            }
            let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
            guard let decoded = try? \(innerType)(decoding: data) else { return }
            me.\(property.name) = decoded
        }
        """
    }

    private static func renderOptionalStringSetter(
        className: String,
        property: ObservableProperty,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jstring?
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            guard let env, let envValue = env.pointee, let new_value else {
                me.\(property.name) = nil
                return
            }
            let cstr = envValue.pointee.GetStringUTFChars(env, new_value, nil)
            defer { envValue.pointee.ReleaseStringUTFChars(env, new_value, cstr) }
            guard let cstr else { return }
            me.\(property.name) = String(cString: cstr)
        }
        """
    }

    private static func renderOptionalWireFormatSetter(
        className: String,
        property: ObservableProperty,
        typeName: String,
    ) -> String {
        """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
        public func __\(className)_\(property.name)_set_jni(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ this_or_class: jobject?,
            _ self_ptr: jlong,
            _ new_value: jbyteArray?
        ) {
            let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
            guard let env, let new_value else {
                me.\(property.name) = nil
                return
            }
            let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
            guard let decoded = try? \(typeName)(decoding: data) else { return }
            me.\(property.name) = decoded
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
