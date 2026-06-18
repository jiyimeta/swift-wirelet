import WireletObservableSchema // InvokeArgClassifier, InvokeArgKind

/// Maps a Swift type text (as recorded by `ProvidedSchemaParser`) to its
/// Kotlin representations for the generated interface and native adapter.
/// Uses `InvokeArgClassifier` so classification is always in lockstep with
/// the Swift proxy emitter.
enum ProvidedKotlinTypeMap {
    // MARK: - Parameter / return info

    struct TypeInfo {
        /// Kotlin type used in the friendly `interface` method signature
        /// (e.g. `Int`, `List<TodoItem>`, `String`).
        let friendlyType: String
        /// Kotlin type used in the `NativeAdapter` wire method signature.
        /// Primitives/bool/string pass through; `@WireFormat` values → `ByteArray`;
        /// arrays → `ByteArray`.
        let wireType: String
        /// FQN imports this type mapping needs.
        let imports: Set<String>
        /// Decodes a wire expression to the friendly type.
        /// For pass-through types, returns the expression unchanged.
        let decode: (String) -> String
        /// Encodes a friendly expression to the wire type.
        /// For pass-through types, returns the expression unchanged.
        let encode: (String) -> String
    }

    // MARK: - Entry point

    /// - Throws: `ProvidedKotlinEmitterError.unsupportedType` for optional types.
    static func typeInfo(
        forTypeText typeText: String,
        service: String,
        method: String,
        config: ProvidedCodegenConfig,
    ) throws -> TypeInfo {
        switch InvokeArgClassifier.classify(typeText) {
        case let .primitive(jni, _):
            let kt = kotlinPrimitive(jniSwiftType: jni)
            return TypeInfo(
                friendlyType: kt, wireType: kt, imports: [],
                decode: { $0 }, encode: { $0 },
            )
        case .bool:
            return TypeInfo(
                friendlyType: "Boolean", wireType: "Boolean", imports: [],
                decode: { $0 }, encode: { $0 },
            )
        case .string:
            return TypeInfo(
                friendlyType: "String", wireType: "String", imports: [],
                decode: { $0 }, encode: { $0 },
            )
        case let .wireFormat(typeName):
            let codec = "\(typeName)Codec"
            return TypeInfo(
                friendlyType: typeName,
                wireType: "ByteArray",
                imports: [
                    "\(config.modelPackage).\(typeName)",
                    "\(config.codecPackage).\(codec)",
                ],
                decode: { expr in "\(codec).decode(\(expr))" },
                encode: { expr in "\(codec).encode(\(expr))" },
            )
        case let .array(elementTypeName):
            let codec = "\(elementTypeName)Codec"
            return TypeInfo(
                friendlyType: "List<\(elementTypeName)>",
                wireType: "ByteArray",
                imports: [
                    "\(config.modelPackage).\(elementTypeName)",
                    "\(config.codecPackage).\(codec)",
                    "\(config.runtimePackage).WireletList",
                ],
                decode: { expr in "WireletList.decode(\(expr), \(codec)::decodePayload)" },
                encode: { expr in "WireletList.encode(\(expr), \(codec)::encodePayload)" },
            )
        case .optionalPrimitive, .optionalString, .optionalWireFormat:
            throw ProvidedKotlinEmitterError.unsupportedType(
                service: service, method: method, type: typeText,
            )
        }
    }

    // MARK: - Helpers

    /// Maps the JNI primitive swift-type tag produced by `InvokeArgClassifier`
    /// to the Kotlin primitive name.
    private static func kotlinPrimitive(jniSwiftType: String) -> String {
        switch jniSwiftType {
        case "jint": return "Int"
        case "jlong": return "Long"
        case "jfloat": return "Float"
        case "jdouble": return "Double"
        default: return "Int" // fallback: unmapped JNI type
        }
    }
}
