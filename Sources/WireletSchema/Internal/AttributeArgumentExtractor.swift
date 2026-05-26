import SwiftSyntax

enum AttributeArgumentExtractor {
    /// Returns the `kotlin:` argument value if present on the attribute,
    /// recognising literal forms `.auto`, `.skip`, `.explicit("...")`.
    static func kotlinTarget(of attribute: AttributeSyntax) -> KotlinTarget {
        guard case let .argumentList(args) = attribute.arguments else {
            return .auto
        }
        for arg in args where arg.label?.text == "kotlin" {
            return parseKotlinTarget(from: arg.expression)
        }
        return .auto
    }

    /// Extracts the `reservedTags:` set from a `@WireFormat(reservedTags: [...])`
    /// attribute. Returns an empty set when the argument is absent or unparseable.
    static func reservedTags(of attribute: AttributeSyntax) -> Set<UInt32> {
        guard case let .argumentList(args) = attribute.arguments else {
            return []
        }
        for arg in args where arg.label?.text == "reservedTags" {
            guard let array = arg.expression.as(ArrayExprSyntax.self) else {
                return []
            }
            var out = Set<UInt32>()
            for element in array.elements {
                if let intLit = element.expression.as(IntegerLiteralExprSyntax.self),
                   let value = UInt32(intLit.literal.text)
                {
                    out.insert(value)
                }
            }
            return out
        }
        return []
    }

    /// Extracts the `tag:` argument from a `@WireFormatField(tag: N)`
    /// attribute on a `var` declaration, if present. Returns `nil` when
    /// the attribute is absent or has no parseable integer literal.
    static func explicitFieldTag(of varDecl: VariableDeclSyntax) -> UInt32? {
        for attr in varDecl.attributes {
            guard let attribute = attr.as(AttributeSyntax.self) else { continue }
            guard let identType = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                continue
            }
            if identType.name.text != "WireFormatField" { continue }
            guard case let .argumentList(args) = attribute.arguments else { continue }
            for arg in args where arg.label?.text == "tag" {
                if let intLit = arg.expression.as(IntegerLiteralExprSyntax.self),
                   let value = UInt32(intLit.literal.text)
                {
                    return value
                }
            }
        }
        return nil
    }

    /// Detects `T?` (sugar) and `Optional<T>` (explicit) forms and returns
    /// `(isOptional, wrappedTypeText)`. For non-optional types returns
    /// `(false, typeText)`.
    static func unwrapOptional(_ type: TypeSyntax) -> (isOptional: Bool, wrapped: String) {
        if let optType = type.as(OptionalTypeSyntax.self) {
            return (true, optType.wrappedType.trimmedDescription)
        }
        if let identType = type.as(IdentifierTypeSyntax.self),
           identType.name.text == "Optional",
           let generics = identType.genericArgumentClause,
           let firstArg = generics.arguments.first,
           generics.arguments.count == 1
        {
            return (true, firstArg.argument.trimmedDescription)
        }
        return (false, type.trimmedDescription)
    }

    private static func parseKotlinTarget(from expr: ExprSyntax) -> KotlinTarget {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            switch member.declName.baseName.text {
            case "auto": return .auto
            case "skip": return .skip
            default: return .auto
            }
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "explicit",
           let first = call.arguments.first,
           let strLit = first.expression.as(StringLiteralExprSyntax.self),
           let segment = strLit.segments.first?.as(StringSegmentSyntax.self)
        {
            return .explicit(segment.content.text)
        }
        return .auto
    }
}
