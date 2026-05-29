import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct WireletObservableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasFinalModifier(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasObservableAttribute(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.missingObservableAttribute))
            return []
        }
        let className = type.trimmed.description
        let properties = WireletObservableProperty.collect(classDecl)
            .filter { !$0.isIgnored }

        var bridges: [String] = []

        // Per-property track bridges
        for property in properties {
            switch property.kind {
            case .primitive(let jniType, _):
                bridges.append(renderPrimitiveBridge(
                    className: className, property: property, jniType: jniType
                ))
            case .string:
                bridges.append(renderStringBridge(className: className, property: property))
            case .wireFormat:
                bridges.append(renderWireFormatBridge(className: className, property: property))
            case .wireFormatArray:
                bridges.append(renderWireFormatArrayBridge(className: className, property: property))
            case .optionalPrimitive, .optionalWireFormat:
                bridges.append(renderOptionalBridge(className: className, property: property))
            case .optionalString:
                bridges.append(renderOptionalStringTrackBridge(className: className, property: property))
            }
        }

        // Constructor and destructor
        bridges.append(renderConstructor(className: className))
        bridges.append(renderDestructor(className: className))

        // Per-property setter bridges (only for var, not let)
        for property in properties where property.isMutable {
            switch property.kind {
            case .primitive(let jniType, _):
                bridges.append(renderPrimitiveSetter(
                    className: className, property: property, jniType: jniType
                ))
            case .string:
                bridges.append(renderStringSetter(className: className, property: property))
            case .wireFormat(let typeName):
                bridges.append(renderWireFormatSetter(
                    className: className, property: property, typeName: typeName
                ))
            case .wireFormatArray(let elementTypeName):
                bridges.append(renderWireFormatArraySetter(
                    className: className, property: property, elementTypeName: elementTypeName
                ))
            case .optionalPrimitive(let jniType):
                bridges.append(renderOptionalPrimitiveSetter(
                    className: className, property: property, jniType: jniType
                ))
            case .optionalString:
                bridges.append(renderOptionalStringSetter(className: className, property: property))
            case .optionalWireFormat(let typeName):
                bridges.append(renderOptionalWireFormatSetter(
                    className: className, property: property, typeName: typeName
                ))
            }
        }

        // @WireletExpose method invoke bridges
        for member in classDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard hasWireletExposeAttribute(funcDecl) else { continue }
            if let bridge = renderInvoke(className: className, funcDecl: funcDecl, context: context) {
                bridges.append(bridge)
            }
        }

        let body: DeclSyntax = """
        extension \(type.trimmed) {
            #if os(Android)
            \(raw: bridges.joined(separator: "\n    "))
            #endif
        }
        """
        guard let ext = body.as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    // MARK: - Track bridges

    private static func renderPrimitiveBridge(
        className: String,
        property: WireletObservableProperty,
        jniType: String
    ) -> String {
        let returnExpr: String = {
            switch property.swiftTypeText {
            case "Bool": return "jboolean(snapshot ? 1 : 0)"
            default:    return "\(jniType)(snapshot)"
            }
        }()
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_track")
            public static func __\(property.name)_track_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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

    // MARK: - Constructor / Destructor

    private static func renderConstructor(className: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_new")
            public static func __new_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?
            ) -> jlong {
                return WireletObservableJNI.retain(\(className)())
            }
        """
    }

    private static func renderDestructor(className: String) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_release")
            public static func __release_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
                _ self_ptr: jlong
            ) {
                WireletObservableJNI.release(self_ptr, as: \(className).self)
            }
        """
    }

    // MARK: - Setter bridges

    private static func renderPrimitiveSetter(
        className: String,
        property: WireletObservableProperty,
        jniType: String
    ) -> String {
        let assignBody: String = {
            switch property.swiftTypeText {
            case "Bool": return "me.\(property.name) = (new_value != 0)"
            default:     return "me.\(property.name) = \(property.swiftTypeText)(new_value)"
            }
        }()
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty,
        typeName: String
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty,
        elementTypeName: String
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty,
        jniType: String
    ) -> String {
        // Optional primitives are transported as jbyteArray? (nil = absent, encoded bytes = present)
        // The inner type name is the swiftTypeText with the trailing "?" stripped.
        let innerType = property.swiftTypeText.hasSuffix("?")
            ? String(property.swiftTypeText.dropLast())
            : property.swiftTypeText
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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
        property: WireletObservableProperty,
        typeName: String
    ) -> String {
        return """
        @_cdecl("WireletObservable_\(className)_\(property.name)_set")
            public static func __\(property.name)_set_jni(
                _ env: UnsafeMutablePointer<JNIEnv?>?,
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

    // MARK: - @WireletExpose invoke bridges

    private static func renderInvoke(
        className: String,
        funcDecl: FunctionDeclSyntax,
        context: some MacroExpansionContext
    ) -> String? {
        let methodName = funcDecl.name.text
        let params = funcDecl.signature.parameterClause.parameters

        if params.isEmpty {
            // Zero-arg invoke
            return """
            @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
                public static func __\(methodName)_invoke_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
                    me.\(methodName)()
                }
            """
        }

        if params.count == 1, let param = params.first {
            let argType = param.type.trimmedDescription
            // Reject primitive types — only @WireFormat (non-primitive identifier) allowed
            if isPrimitiveType(argType) || argType == "String" {
                context.diagnose(Diagnostic(
                    node: Syntax(funcDecl.name),
                    message: WireletObservableDiagnostic.unsupportedExposedMethodSignature
                ))
                return nil
            }
            let argLabel = param.firstName.text
            // One-arg @WireFormat invoke
            return """
            @_cdecl("WireletObservable_\(className)_\(methodName)_invoke")
                public static func __\(methodName)_invoke_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ arg0: jbyteArray?
                ) {
                    guard let env, let arg0 else { return }
                    let data = WireletObservableJNI.dataFromByteArray(arg0, env: env)
                    guard let decoded = try? \(argType)(decoding: data) else { return }
                    let me = WireletObservableJNI.unwrap(self_ptr) as \(className)
                    me.\(methodName)(\(argLabel == "_" ? "" : argLabel + ": ")decoded)
                }
            """
        }

        // More than one arg — unsupported
        context.diagnose(Diagnostic(
            node: Syntax(funcDecl.name),
            message: WireletObservableDiagnostic.unsupportedExposedMethodSignature
        ))
        return nil
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

    private static func hasWireletExposeAttribute(_ funcDecl: FunctionDeclSyntax) -> Bool {
        funcDecl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "WireletExpose"
        }
    }

    private static func hasFinalModifier(_ decl: ClassDeclSyntax) -> Bool {
        decl.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
    }

    private static func hasObservableAttribute(_ decl: ClassDeclSyntax) -> Bool {
        decl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "Observable"
        }
    }
}
