import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `@WireFormat` on a struct: emits one extension that adds
/// `WireFormatEncodable` + `WireFormatDecodable` conformance whose encoded
/// layout is a TLV (tag / length / value) record. Implicit field tags are
/// assigned 1, 2, 3, ... in declaration order. The struct's wire type is
/// `.lengthDelimited` — `encode(into:)` wraps `encodePayload(into:)` in a
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

        let properties = collectStoredProperties(of: structDecl, context: context)

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
        properties: [(name: String, typeText: String, tag: Int)],
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
        properties: [(name: String, typeText: String, tag: Int)],
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

    // MARK: - Property collection

    private static func collectStoredProperties(
        of structDecl: StructDeclSyntax,
        context: some MacroExpansionContext,
    ) -> [(name: String, typeText: String, tag: Int)] {
        var out: [(name: String, typeText: String, tag: Int)] = []
        var nextTag = 1

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            let isStatic = varDecl.modifiers.contains { modifier in
                modifier.name.text == "static" || modifier.name.text == "class"
            }
            if isStatic { continue }

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
                out.append((name: name, typeText: typeText, tag: nextTag))
                nextTag += 1
            }
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
