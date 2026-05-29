/// Classification of a single `@WireletExpose` method parameter type.
///
/// The Swift bridges emitter, Kotlin emitter, and JNI sidecar builder all
/// consult this enum so their decisions stay in lockstep. Adding a new
/// category here is the single editable point.
public enum InvokeArgKind: Equatable, Sendable {
    /// `Int8/16/32/64`, `UInt8/16/32/64`, `Float`, `Double`.
    /// `jniSwiftType` is the Swift name of the JNI primitive
    /// (e.g. `jint`); `swiftCast` is the Swift type the bridge converts to
    /// before calling the user method (e.g. `Int32`).
    case primitive(jniSwiftType: String, swiftCast: String)
    /// `Bool` — its own case because conversion is `(arg != 0)`, not
    /// `Bool(arg)`.
    case bool
    /// `String`.
    case string
    /// A non-optional `@WireFormat` struct/enum.
    case wireFormat(typeName: String)
    /// `Int32?` etc.
    case optionalPrimitive(innerTypeName: String)
    /// `String?`.
    case optionalString
    /// `T?` where `T` is `@WireFormat`.
    case optionalWireFormat(typeName: String)
    /// `[T]` where `T` is `@WireFormat`.
    case array(elementTypeName: String)
}

public enum InvokeArgClassifier {
    public static func classify(_ typeText: String) -> InvokeArgKind {
        // Order matters: more specific patterns first.
        if typeText.hasSuffix("?") {
            let inner = String(typeText.dropLast())
            return classifyOptional(innerTypeName: inner)
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            let inner = String(typeText.dropFirst("Optional<".count).dropLast())
            return classifyOptional(innerTypeName: inner)
        }
        if typeText.hasPrefix("["), typeText.hasSuffix("]") {
            let element = String(typeText.dropFirst().dropLast())
            return .array(elementTypeName: element)
        }
        if typeText == "Bool" { return .bool }
        if let primitive = primitiveJNI(typeText) {
            return .primitive(jniSwiftType: primitive, swiftCast: typeText)
        }
        if typeText == "String" { return .string }
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(innerTypeName: String) -> InvokeArgKind {
        if primitiveJNI(innerTypeName) != nil {
            return .optionalPrimitive(innerTypeName: innerTypeName)
        }
        if innerTypeName == "String" { return .optionalString }
        return .optionalWireFormat(typeName: innerTypeName)
    }

    private static func primitiveJNI(_ typeText: String) -> String? {
        switch typeText {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "jint"
        case "Int64", "UInt32", "UInt64":                 return "jlong"
        case "Bool":   return "jboolean"
        case "Float":  return "jfloat"
        case "Double": return "jdouble"
        default: return nil
        }
    }
}
