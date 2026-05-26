import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `@WireFormat` on a struct: emits one extension that adds
/// `WireFormatEncodable` + `WireFormatDecodable` conformance whose encoded
/// layout is a TLV (tag / length / value) record. Implicit field tags are
/// assigned 1, 2, 3, ... in declaration order, skipping any explicit
/// (`@WireFormatField(tag:)`) or reserved (`@WireFormat(reservedTags:)`)
/// tag values. The struct's wire type is `.lengthDelimited` —
/// `encode(into:)` wraps `encodePayload(into:)` in a
/// `writer.writeLengthPrefixed { ... }` so a nested struct is
/// self-delimiting from its enclosing record.
public struct WireFormatMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireFormatDiagnostic.notAStruct,
            ))
            return []
        }

        let reservedTags = parseReservedTags(from: node)
        let properties = collectStoredProperties(
            of: structDecl,
            reservedTags: reservedTags,
            context: context,
        )

        let encodePayloadBody = renderEncodePayloadBody(properties: properties)
        let decodePayloadBody = renderDecodePayloadBody(properties: properties)

        let extensionSource: DeclSyntax = """
        extension \(type.trimmed): WireFormatEncodable, WireFormatDecodable {
            public static var wireType: WireType { .lengthDelimited }

            public func encodePayload(into writer: inout WireFormatWriter) {
                \(raw: encodePayloadBody)
            }

            public func encode(into writer: inout WireFormatWriter) {
                writer.writeLengthPrefixed { inner in
                    encodePayload(into: &inner)
                }
            }

            public init(decodingPayload reader: inout WireFormatReader) throws {
                \(raw: decodePayloadBody)
            }

            public init(from reader: inout WireFormatReader) throws {
                let len = Int(try reader.readVarint())
                let slice = try reader.readBytes(count: len)
                var inner = WireFormatReader(data: slice)
                try self.init(decodingPayload: &inner)
            }
        }
        """

        guard let extensionDecl = extensionSource.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extensionDecl]
    }

    // MARK: - Body rendering

    private static func renderEncodePayloadBody(
        properties: [Property],
    ) -> String {
        if properties.isEmpty {
            return ""
        }
        var lines: [String] = []
        for property in properties {
            if property.isOptional {
                // Optional field: skip tag emission entirely when nil.
                let wrapped = property.wrappedTypeText
                lines.append("if let value = self.\(property.name) {")
                lines.append(
                    "    writer.writeTag(tag: \(property.tag), wireType: \(wrapped).wireType)",
                )
                lines.append("    value.encode(into: &writer)")
                lines.append("}")
            } else {
                lines.append(
                    "writer.writeTag(tag: \(property.tag), wireType: \(property.typeText).wireType)",
                )
                lines.append("\(property.name).encode(into: &writer)")
            }
        }
        return lines.joined(separator: "\n        ")
    }

    private static func renderDecodePayloadBody(
        properties: [Property],
    ) -> String {
        if properties.isEmpty {
            return ""
        }
        var lines: [String] = []
        for property in properties {
            // The decode temporary is always `T?`. For optional fields the
            // wrapped type is `T` (same shape). For required fields we use
            // the property's declared type as the wrapped form.
            let wrapped = property.isOptional ? property.wrappedTypeText : property.typeText
            lines.append("var _\(property.name): \(wrapped)? = nil")
        }
        lines.append("while !reader.isAtEnd {")
        lines.append("    let (tag, wt) = try reader.readTag()")
        lines.append("    switch tag {")
        for property in properties {
            let wrapped = property.isOptional ? property.wrappedTypeText : property.typeText
            lines.append(
                "    case \(property.tag): _\(property.name) = try \(wrapped)(from: &reader)",
            )
        }
        lines.append("    default: try reader.skipUnknownField(wireType: wt)")
        lines.append("    }")
        lines.append("}")
        for property in properties {
            if property.isOptional {
                // Absence on the wire = nil — no missing-field check.
                lines.append("self.\(property.name) = _\(property.name)")
            } else {
                lines.append(
                    "guard let _\(property.name) else { throw WireFormatError.unknownTag(tag: \(property.tag), wireType: \(property.typeText).wireType) }",
                )
                lines.append("self.\(property.name) = _\(property.name)")
            }
        }
        return lines.joined(separator: "\n        ")
    }

    // MARK: - Attribute argument parsing

    /// Returns the set of reserved tag numbers declared on the
    /// `@WireFormat(reservedTags: [...])` attribute. Returns an empty set
    /// when the argument is absent or unparseable.
    private static func parseReservedTags(from attribute: AttributeSyntax) -> Set<UInt32> {
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

    private static func collectStoredProperties(
        of structDecl: StructDeclSyntax,
        reservedTags: Set<UInt32>,
        context: some MacroExpansionContext,
    ) -> [Property] {
        // Pass 1: gather (name, type, explicit tag?) for every stored property.
        typealias Raw = (
            name: String,
            typeText: String,
            wrappedTypeText: String,
            isOptional: Bool,
            explicitTag: UInt32?,
            varDecl: VariableDeclSyntax
        )
        var raws: [Raw] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            let isStatic = varDecl.modifiers.contains { modifier in
                modifier.name.text == "static" || modifier.name.text == "class"
            }
            if isStatic { continue }

            let explicit = explicitTag(of: varDecl)

            for binding in varDecl.bindings {
                if isComputed(binding: binding) { continue }

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
                    varDecl: varDecl
                ))
            }
        }

        // Pass 2: validate explicit tags, detect conflicts + reserved-use + zero.
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

        // Pass 3: assign tags. Explicit tags use their declared value (even
        // if invalid — diagnostics already fired, but emitting the body
        // keeps downstream errors localized to the macro's diagnostic).
        // Implicit tags use the smallest UInt32 ≥ counter that is neither
        // in seenExplicit nor in reservedTags.
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
