import SwiftSyntax

struct WireletObservableProperty {
    enum Kind {
        case primitive(jniType: String, swiftReadExpr: (String) -> String)
        case string
        case wireFormat(typeName: String)
        case wireFormatArray(elementTypeName: String)
        case optionalPrimitive(jniType: String)
        case optionalString
        case optionalWireFormat(typeName: String)
    }

    let name: String
    let swiftTypeText: String
    let kind: Kind
    let isMutable: Bool
    let isIgnored: Bool
}

extension WireletObservableProperty {
    static func collect(_ classDecl: ClassDeclSyntax) -> [WireletObservableProperty] {
        var out: [WireletObservableProperty] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else { continue }
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            guard let typeSyntax = binding.typeAnnotation?.type else { continue }
            let typeText = typeSyntax.trimmedDescription
            let isIgnored = varDecl.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ObservationIgnored"
            }
            let isMutable = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
            guard let kind = classify(typeText) else { continue }
            out.append(WireletObservableProperty(
                name: identifier,
                swiftTypeText: typeText,
                kind: kind,
                isMutable: isMutable,
                isIgnored: isIgnored
            ))
        }
        return out
    }

    private static func classify(_ typeText: String) -> Kind? {
        // Optional<T> normalization. Both `T?` and `Optional<T>` accepted.
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
            // Primitive array support is intentionally omitted in Phase 1;
            // the spec lists [@WireFormat] as the only array shape.
            return .wireFormatArray(elementTypeName: element)
        }
        if let primitive = primitiveJNIType(typeText) {
            return .primitive(jniType: primitive, swiftReadExpr: { reader in reader })
        }
        if typeText == "String" {
            return .string
        }
        // Treat anything else as a @WireFormat user type.
        return .wireFormat(typeName: typeText)
    }

    private static func classifyOptional(_ inner: String) -> Kind? {
        if let primitive = primitiveJNIType(inner) {
            return .optionalPrimitive(jniType: primitive)
        }
        if inner == "String" {
            return .optionalString
        }
        return .optionalWireFormat(typeName: inner)
    }

    private static func primitiveJNIType(_ typeText: String) -> String? {
        switch typeText {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "jint"
        case "Int64", "UInt32", "UInt64": return "jlong"
        case "Bool": return "jboolean"
        case "Float": return "jfloat"
        case "Double": return "jdouble"
        default: return nil
        }
    }
}
