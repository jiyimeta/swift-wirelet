import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `@WireFormatChoice` on a sum-type enum: emits a
/// `WireFormat` conformance whose encoded layout is a length-delimited
/// blob containing:
///
/// ```
/// varint discriminator   ← case's declaration-order index (0, 1, 2, …)
/// TLV fields             ← associated values of the selected case, tagged
///                          1..N in associated-value declaration order
/// ```
///
/// All associated value types must themselves conform to `WireFormat`. The
/// compiler will reject the macro-generated code at type-check time if a
/// payload type does not conform.
///
/// Cases without associated values encode as just the discriminator inside
/// the length-prefixed wrapper.
///
/// Wire-stable as long as case declaration order is preserved. Adding a new
/// case at the end is forward-compatible (old readers reject it with
/// `unknownChoiceDiscriminator`); reordering or removing cases breaks the
/// wire.
public struct WireFormatChoiceMacro: ExtensionMacro {
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

        let cases = collectCases(of: enumDecl)

        // Warn when the enum has cases but none of them carry associated
        // values — @WireFormatEnum (raw-value backed) is the more
        // idiomatic choice for plain enums and produces a smaller wire
        // payload (no length wrapper around just the discriminator).
        if !cases.isEmpty, cases.allSatisfy({ $0.parameters.isEmpty }) {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireFormatDiagnostic.choiceWithoutAssociatedValues,
            ))
        }

        let encodePayloadBody = renderEncodePayloadBody(cases: cases)
        let decodePayloadBody = renderDecodePayloadBody(cases: cases)

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

    // MARK: - Case collection

    struct CaseInfo {
        let name: String
        let parameters: [Parameter]

        struct Parameter {
            let label: String?
            let typeText: String
        }
    }

    private static func collectCases(of enumDecl: EnumDeclSyntax) -> [CaseInfo] {
        var out: [CaseInfo] = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let parameters: [CaseInfo.Parameter]
                if let clause = element.parameterClause {
                    parameters = clause.parameters.map { param in
                        let label = labelFor(param: param)
                        let typeText = param.type.trimmedDescription
                        return CaseInfo.Parameter(label: label, typeText: typeText)
                    }
                } else {
                    parameters = []
                }
                out.append(CaseInfo(name: element.name.text, parameters: parameters))
            }
        }
        return out
    }

    private static func labelFor(param: EnumCaseParameterSyntax) -> String? {
        // For `case .beat(measureIndex: Int, tickInMeasure: Int)`:
        //   firstName.text == "measureIndex" — that's the external label.
        // For `case .explicit(VoiceElementID)`: firstName == nil.
        // For `case .foo(_ x: Int)`: firstName.text == "_" — treat as no label.
        guard let name = param.firstName?.text, name != "_" else { return nil }
        return name
    }

    // MARK: - Body rendering

    private static func renderEncodePayloadBody(cases: [CaseInfo]) -> String {
        if cases.isEmpty {
            // An empty enum can't be inhabited; emit `switch self {}` for exhaustiveness.
            return "switch self {}"
        }
        var lines = ["switch self {"]
        for (index, c) in cases.enumerated() {
            if c.parameters.isEmpty {
                lines.append("case .\(c.name):")
                lines.append("    writer.writeVarint(UInt64(\(index)))")
            } else {
                let bindings = c.parameters.indices.map { "let v\($0)" }.joined(separator: ", ")
                lines.append("case .\(c.name)(\(bindings)):")
                lines.append("    writer.writeVarint(UInt64(\(index)))")
                for (valueIndex, param) in c.parameters.enumerated() {
                    let tag = valueIndex + 1
                    lines.append(
                        "    writer.writeTag(tag: \(tag), wireType: \(param.typeText).wireType)",
                    )
                    lines.append("    v\(valueIndex).encode(into: &writer)")
                }
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n        ")
    }

    private static func renderDecodePayloadBody(cases: [CaseInfo]) -> String {
        var lines: [String] = [
            "let disc = try reader.readVarint()",
            "switch disc {",
        ]
        for (index, c) in cases.enumerated() {
            lines.append("case \(index):")
            if c.parameters.isEmpty {
                lines.append("    self = .\(c.name)")
            } else {
                for (valueIndex, param) in c.parameters.enumerated() {
                    lines.append("    var _arg\(valueIndex): \(param.typeText)? = nil")
                }
                lines.append("    while !reader.isAtEnd {")
                lines.append("        let (tag, wt) = try reader.readTag()")
                lines.append("        switch tag {")
                for (valueIndex, param) in c.parameters.enumerated() {
                    let tag = valueIndex + 1
                    lines.append(
                        "        case \(tag): _arg\(valueIndex) = try \(param.typeText)(from: &reader)",
                    )
                }
                lines.append("        default: try reader.skipUnknownField(wireType: wt)")
                lines.append("        }")
                lines.append("    }")
                for (valueIndex, param) in c.parameters.enumerated() {
                    let tag = valueIndex + 1
                    lines.append(
                        "    guard let _arg\(valueIndex) else { throw WireFormatError.unknownTag(tag: \(tag), wireType: \(param.typeText).wireType) }",
                    )
                }
                let construction = c.parameters.enumerated().map { idx, param -> String in
                    if let label = param.label {
                        return "\(label): _arg\(idx)"
                    } else {
                        return "_arg\(idx)"
                    }
                }.joined(separator: ", ")
                lines.append("    self = .\(c.name)(\(construction))")
            }
        }
        lines.append("default:")
        lines.append("    throw WireFormatError.unknownChoiceDiscriminator(UInt32(truncatingIfNeeded: disc))")
        lines.append("}")
        return lines.joined(separator: "\n        ")
    }
}
