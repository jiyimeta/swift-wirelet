import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension WireFormatMacro {
    // MARK: - Attribute argument parsing

    /// Returns the set of reserved tag numbers declared on the
    /// `@WireFormat(reservedTags: [...])` attribute. Returns an empty set
    /// when the argument is absent or unparseable.
    static func parseReservedTags(from attribute: AttributeSyntax) -> Set<UInt32> {
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

    /// Returns true when the variable declaration carries any
    /// `@WireFormatField(...)` attribute, regardless of its argument
    /// list. Used to distinguish "user marked this property" from
    /// "macro skipped it silently".
    private static func hasWireFormatFieldAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
        for attr in varDecl.attributes {
            guard let attribute = attr.as(AttributeSyntax.self) else { continue }
            guard let identType = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                continue
            }
            if identType.name.text == "WireFormatField" { return true }
        }
        return false
    }

    /// Extracts the `tag:` argument from a `@WireFormatField(tag: N)`
    /// attribute, if present on the property. Returns `nil` when the
    /// attribute is absent or has no parseable integer literal.
    private static func explicitTag(of varDecl: VariableDeclSyntax) -> UInt32? {
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

    // MARK: - Property collection

    /// Captured info for one stored property of a `@WireFormat` struct.
    /// `typeText` is the declared type as written. `isOptional` is true
    /// for sugared `T?` or explicit `Optional<T>` forms; for those,
    /// `wrappedTypeText` is `T`. For non-optional fields `wrappedTypeText`
    /// equals `typeText`.
    struct Property {
        var name: String
        var typeText: String
        var wrappedTypeText: String
        var isOptional: Bool
        var tag: UInt32
    }

    // Raw gathered info for one stored property before tag assignment.
    // A named struct would read better, but Swift forbids nesting a type
    // inside the generic `collectStoredProperties`
    // (`context: some MacroExpansionContext`), so this stays a tuple.
    // swiftlint:disable:next large_tuple
    private typealias Raw = (
        name: String,
        typeText: String,
        wrappedTypeText: String,
        isOptional: Bool,
        explicitTag: UInt32?,
        varDecl: VariableDeclSyntax,
    )

    static func collectStoredProperties(
        of structDecl: StructDeclSyntax,
        reservedTags: Set<UInt32>,
        context: some MacroExpansionContext,
    ) -> [Property] {
        // Pass 1: gather (name, type, explicit tag?) for every stored property.
        let raws = gatherRawProperties(of: structDecl, context: context)
        // Pass 2: validate explicit tags, detect conflicts + reserved-use + zero.
        validateExplicitTags(raws, reservedTags: reservedTags, context: context)
        // Pass 3: assign tags and build the final Property list.
        return assignTags(to: raws, reservedTags: reservedTags)
    }

    /// Pass 1: gather `(name, type, explicit tag?)` for every stored
    /// property of the struct, diagnosing computed-property misuse and
    /// missing type annotations along the way.
    private static func gatherRawProperties(
        of structDecl: StructDeclSyntax,
        context: some MacroExpansionContext,
    ) -> [Raw] {
        var raws: [Raw] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            let isStatic = varDecl.modifiers.contains { modifier in
                modifier.name.text == "static" || modifier.name.text == "class"
            }
            if isStatic { continue }

            let explicit = explicitTag(of: varDecl)
            let hasFieldAttribute = hasWireFormatFieldAttribute(varDecl)

            for binding in varDecl.bindings {
                if isComputed(binding: binding) {
                    // Warn when the user attached @WireFormatField to a
                    // computed property — the attribute is silently
                    // dropped, which is surprising. (Stored properties
                    // are still the only thing the macro can serialize.)
                    if hasFieldAttribute,
                       let identPattern = binding.pattern.as(IdentifierPatternSyntax.self)
                    {
                        context.diagnose(Diagnostic(
                            node: Syntax(varDecl),
                            message: WireFormatDiagnostic.fieldOnComputedProperty(
                                propertyName: identPattern.identifier.text,
                            ),
                        ))
                    }
                    continue
                }

                guard let identPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                let name = identPattern.identifier.text

                guard let typeAnnotation = binding.typeAnnotation else {
                    context.diagnose(Diagnostic(
                        node: Syntax(binding),
                        message: WireFormatDiagnostic.missingTypeAnnotation(propertyName: name),
                    ))
                    continue
                }

                let typeSyntax = typeAnnotation.type
                let typeText = typeSyntax.trimmedDescription
                let (isOptional, wrappedTypeText) = unwrapOptional(typeSyntax)
                raws.append((
                    name: name,
                    typeText: typeText,
                    wrappedTypeText: wrappedTypeText,
                    isOptional: isOptional,
                    explicitTag: explicit,
                    varDecl: varDecl,
                ))
            }
        }

        return raws
    }

    /// Pass 2: validate explicit tags, diagnosing zero/out-of-range,
    /// reserved-tag reuse, and duplicate explicit tags. Diagnostics only —
    /// the gathered list is unchanged.
    private static func validateExplicitTags(
        _ raws: [Raw],
        reservedTags: Set<UInt32>,
        context: some MacroExpansionContext,
    ) {
        var seenExplicit: Set<UInt32> = []
        var conflictReported: Set<UInt32> = []
        for raw in raws {
            guard let tag = raw.explicitTag else { continue }
            if tag == 0 {
                context.diagnose(Diagnostic(
                    node: Syntax(raw.varDecl),
                    message: WireFormatDiagnostic.tagOutOfRange(fieldName: raw.name),
                ))
                continue
            }
            if reservedTags.contains(tag) {
                context.diagnose(Diagnostic(
                    node: Syntax(raw.varDecl),
                    message: WireFormatDiagnostic.reservedTagUsed(tag: tag, fieldName: raw.name),
                ))
            }
            if seenExplicit.contains(tag), !conflictReported.contains(tag) {
                context.diagnose(Diagnostic(
                    node: Syntax(raw.varDecl),
                    message: WireFormatDiagnostic.tagConflict(tag: tag),
                ))
                conflictReported.insert(tag)
            }
            seenExplicit.insert(tag)
        }
    }

    /// Pass 3: assign tags. Explicit tags use their declared value (even
    /// if invalid — diagnostics already fired, but emitting the body
    /// keeps downstream errors localized to the macro's diagnostic).
    /// Implicit tags use the smallest UInt32 ≥ counter that is neither
    /// in seenExplicit nor in reservedTags.
    private static func assignTags(
        to raws: [Raw],
        reservedTags: Set<UInt32>,
    ) -> [Property] {
        var seenExplicit: Set<UInt32> = []
        for raw in raws {
            if let tag = raw.explicitTag, tag != 0 {
                seenExplicit.insert(tag)
            }
        }

        var out: [Property] = []
        var counter: UInt32 = 1
        for raw in raws {
            let tag: UInt32
            if let explicit = raw.explicitTag {
                tag = explicit
            } else {
                while seenExplicit.contains(counter) || reservedTags.contains(counter) || counter == 0 {
                    counter &+= 1
                }
                tag = counter
                counter &+= 1
            }
            out.append(Property(
                name: raw.name,
                typeText: raw.typeText,
                wrappedTypeText: raw.wrappedTypeText,
                isOptional: raw.isOptional,
                tag: tag,
            ))
        }
        return out
    }

    /// Detects `T?` (sugar) and `Optional<T>` (explicit) forms and returns
    /// `(isOptional, wrappedTypeText)`. For non-optional types returns
    /// `(false, typeText)` so callers can use the result uniformly.
    private static func unwrapOptional(_ type: TypeSyntax) -> (isOptional: Bool, wrapped: String) {
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

    private static func isComputed(binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return false }
        switch accessorBlock.accessors {
        case .getter:
            return true
        case let .accessors(list):
            return list.contains { accessor in
                let name = accessor.accessorSpecifier.text
                return name == "get" || name == "set" || name == "_modify" || name == "_read"
            }
        }
    }
}
