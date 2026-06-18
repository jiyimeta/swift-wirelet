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
                let wireTypeExpr = "\(property.typeText).wireType"
                let missing = "WireFormatError.unknownTag(tag: \(property.tag), wireType: \(wireTypeExpr))"
                lines.append("guard let _\(property.name) else { throw \(missing) }")
                lines.append("self.\(property.name) = _\(property.name)")
            }
        }
        return lines.joined(separator: "\n        ")
    }
}
