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
        properties: [(name: String, typeText: String, tag: UInt32)],
    ) -> String {
        if properties.isEmpty {
            return ""
        }
        var lines: [String] = []
        for property in properties {
            lines.append(
                "writer.writeTag(tag: \(property.tag), wireType: \(property.typeText).wireType)",
            )
            lines.append("\(property.name).encodePayload(into: &writer)")
        }
        return lines.joined(separator: "\n        ")
    }

    private static func renderDecodePayloadBody(
        properties: [(name: String, typeText: String, tag: UInt32)],
    ) -> String {
        if properties.isEmpty {
            return ""
        }
        var lines: [String] = []
        for property in properties {
            lines.append("var _\(property.name): \(property.typeText)? = nil")
        }
        lines.append("while !reader.isAtEnd {")
        lines.append("    let (tag, wt) = try reader.readTag()")
        lines.append("    switch tag {")
        for property in properties {
            lines.append(
                "    case \(property.tag): _\(property.name) = try \(property.typeText)(decodingPayload: &reader)",
            )
        }
        lines.append("    default: try reader.skipUnknownField(wireType: wt)")
        lines.append("    }")
        lines.append("}")
        for property in properties {
            lines.append(
                "guard let _\(property.name) else { throw WireFormatError.unknownTag(tag: \(property.tag), wireType: \(property.typeText).wireType) }",
            )
            lines.append("self.\(property.name) = _\(property.name)")
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

    private static func collectStoredProperties(
        of structDecl: StructDeclSyntax,
        reservedTags: Set<UInt32>,
        context: some MacroExpansionContext,
    ) -> [(name: String, typeText: String, tag: UInt32)] {
        // Pass 1: gather (name, type, explicit tag?) for every stored property.
        typealias Raw = (
            name: String,
            typeText: String,
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

                let typeText = typeAnnotation.type.trimmedDescription
                raws.append((
                    name: name,
                    typeText: typeText,
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
        var out: [(name: String, typeText: String, tag: UInt32)] = []
        var counter: UInt32 = 1
        for raw in raws {
            if let tag = raw.explicitTag {
                out.append((name: raw.name, typeText: raw.typeText, tag: tag))
                continue
            }
            while seenExplicit.contains(counter) || reservedTags.contains(counter) || counter == 0 {
                counter &+= 1
            }
            out.append((name: raw.name, typeText: raw.typeText, tag: counter))
            counter &+= 1
        }
        return out
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
