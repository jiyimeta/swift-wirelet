import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `@WireFormatEnum` on a `RawRepresentable` enum (typical:
/// `enum Foo: UInt8, CaseIterable, Equatable { ... }`). Emits a
/// `WireFormat` conformance whose payload is the enum's raw value encoded
/// via the raw type's own `encodePayload(into:)`. The enum's `wireType` is
/// the raw type's `wireType` (varint for integer raws, lengthDelimited for
/// String). The macro does not emit a tag itself — the enclosing TLV
/// record's field carries the tag.
///
/// Wire-stable contract: changing the raw type or the rawValue assigned to
/// a case is a breaking change. Adding new cases is forward-compatible
/// (old readers throw `WireFormatError.invalidCount` on unknown raws).
public struct WireFormatEnumMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireFormatDiagnostic.notAnEnum,
            ))
            return []
        }

        guard let rawTypeText = extractRawType(from: enumDecl) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireFormatDiagnostic.missingRawType,
            ))
            return []
        }

        let selfTypeText = type.trimmedDescription
        let invalidCountExpr = invalidCountExpression(forRawType: rawTypeText)

        let extensionSource: DeclSyntax = """
        extension \(type.trimmed): WireFormatEncodable, WireFormatDecodable {
            public static var wireType: WireType { \(raw: rawTypeText).wireType }

            public func encodePayload(into writer: inout WireFormatWriter) {
                rawValue.encodePayload(into: &writer)
            }

            public init(decodingPayload reader: inout WireFormatReader) throws {
                let raw = try \(raw: rawTypeText)(decodingPayload: &reader)
                guard let v = \(raw: selfTypeText)(rawValue: raw) else {
                    throw WireFormatError.invalidCount(\(raw: invalidCountExpr))
                }
                self = v
            }

            public func encode(into writer: inout WireFormatWriter) {
                encodePayload(into: &writer)
            }

            public init(from reader: inout WireFormatReader) throws {
                try self.init(decodingPayload: &reader)
            }
        }
        """

        guard let extensionDecl = extensionSource.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extensionDecl]
    }

    // MARK: - Raw type extraction

    /// Returns the textual representation of the enum's raw type (the
    /// first non-protocol-conformance inherited type), or `nil` if the
    /// inheritance clause is absent.
    ///
    /// The macro doesn't reach the type checker — it only sees syntax.
    /// We accept any first inherited type as the raw type. Swift itself
    /// will reject a non-RawRepresentable conformance later if the user
    /// listed (say) `Equatable` first by mistake.
    private static func extractRawType(from enumDecl: EnumDeclSyntax) -> String? {
        guard let inheritance = enumDecl.inheritanceClause else { return nil }
        guard let first = inheritance.inheritedTypes.first else { return nil }
        return first.type.trimmedDescription
    }

    /// Renders an `Int32`-typed expression suitable for embedding in
    /// `WireFormatError.invalidCount(_:)`. Integer raws cast directly via
    /// `truncatingIfNeeded` (cheap diagnostic — overflow into negative is
    /// fine for an error code). String / other raws fall back to
    /// `hashValue` so the error still carries *some* identifying signal
    /// without changing the error case shape.
    private static func invalidCountExpression(forRawType rawType: String) -> String {
        switch rawType {
        case "UInt8", "UInt16", "UInt32", "UInt64",
             "Int8", "Int16", "Int32", "Int64":
            return "Int32(truncatingIfNeeded: raw)"
        default:
            return "Int32(truncatingIfNeeded: raw.hashValue)"
        }
    }
}
