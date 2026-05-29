import Foundation

enum ObservableTypeClassifier {
    /// Returns the schema kind for a Swift type as written in source, or
    /// `nil` for unsupported shapes (primitive arrays, dictionaries, etc.).
    /// The caller (parser) is responsible for surfacing unsupported types
    /// to the user.
    static func classify(_ typeText: String) -> ObservablePropertyKind? {
        // Optional<T> normalization — both `T?` and `Optional<T>` accepted.
        if typeText.hasSuffix("?") {
            let inner = String(typeText.dropLast())
            return classifyOptional(inner)
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            let inner = String(typeText.dropFirst("Optional<".count).dropLast())
            return classifyOptional(inner)
        }
        if typeText.hasPrefix("["), typeText.hasSuffix("]") {
            let element = String(typeText.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
            if element.contains(":") { return nil } // dictionaries unsupported in v0.1
            if isPrimitive(element) || element == "String" { return nil }
            return .wireFormatArray(elementTypeName: element)
        }
        if isPrimitive(typeText) {
            return .primitive
        }
        if typeText == "String" {
            return .string
        }
        // Anything else: treat as a user-defined @WireFormat type. The
        // emitter resolves it against the configured codec package.
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(_ inner: String) -> ObservablePropertyKind? {
        if isPrimitive(inner) { return .optionalPrimitive }
        if inner == "String" { return .optionalString }
        // Optional<[T]> / Optional<Optional<T>> are intentionally unsupported.
        if inner.hasPrefix("["), inner.hasSuffix("]") { return nil }
        if inner.hasSuffix("?") { return nil }
        if inner.hasPrefix("Optional<"), inner.hasSuffix(">") { return nil }
        return .optionalWireFormat(typeName: inner)
    }

    static func isPrimitive(_ typeText: String) -> Bool {
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
