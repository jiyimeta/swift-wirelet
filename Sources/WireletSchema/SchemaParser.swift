import Foundation
import SwiftParser
import SwiftSyntax

public enum SchemaParser {
    /// Parses a WireFormat schema from Swift source. The `fileName` parameter is retained for
    /// future per-file diagnostic output in Task 11 (EmitWireletKotlin CLI).
    public static func parse(source: String, fileName: String) -> Schema {
        let tree = Parser.parse(source: source)
        let visitor = WireTypeVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return Schema(types: visitor.types)
    }
}

final class WireTypeVisitor: SyntaxVisitor {
    var types: [WireType] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        for attribute in node.attributes {
            guard
                let attr = attribute.as(AttributeSyntax.self),
                attr.attributeName.trimmedDescription == "WireFormat"
            else { continue }
            let reservedTags = AttributeArgumentExtractor.reservedTags(of: attr)
            let fields = collectFields(from: node, reservedTags: reservedTags)
            let target = AttributeArgumentExtractor.kotlinTarget(of: attr)
            types.append(.struct(WireStruct(
                name: node.name.text,
                fields: fields,
                reservedTags: reservedTags.sorted(),
                kotlinTarget: target,
            )))
        }
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        for attribute in node.attributes {
            guard
                let attr = attribute.as(AttributeSyntax.self)
            else { continue }
            let attrName = attr.attributeName.trimmedDescription
            let target = AttributeArgumentExtractor.kotlinTarget(of: attr)
            switch attrName {
            case "WireFormatChoice":
                types.append(.choice(WireChoice(
                    name: node.name.text,
                    cases: collectChoiceCases(from: node),
                    kotlinTarget: target,
                )))
            case "WireFormatEnum":
                types.append(.rawEnum(WireRawEnum(
                    name: node.name.text,
                    cases: collectRawCases(from: node),
                    kotlinTarget: target,
                )))
            default:
                continue
            }
        }
        return .visitChildren
    }

    private func collectChoiceCases(from enumDecl: EnumDeclSyntax) -> [WireChoiceCase] {
        var out: [WireChoiceCase] = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let payload: [PayloadField] = element.parameterClause?.parameters.map { param in
                    PayloadField(
                        label: param.firstName?.text,
                        typeText: param.type.trimmedDescription,
                    )
                } ?? []
                out.append(WireChoiceCase(
                    name: element.name.text,
                    payload: payload,
                ))
            }
        }
        return out
    }

    private func collectRawCases(from enumDecl: EnumDeclSyntax) -> [String] {
        var out: [String] = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                out.append(element.name.text)
            }
        }
        return out
    }

    /// Collects stored properties of a `@WireFormat` struct and assigns TLV
    /// tags using the same fill-gaps algorithm as `WireFormatMacro`:
    /// 1. Gather explicit `@WireFormatField(tag:)` tags.
    /// 2. Walk fields in declaration order; explicit tag wins, otherwise
    ///    pick the smallest counter ≥ 1 not in `reservedTags ∪ explicitTags`.
    private func collectFields(
        from `struct`: StructDeclSyntax,
        reservedTags: Set<UInt32>,
    ) -> [WireField] {
        typealias Raw = (
            name: String,
            typeText: String,
            wrappedTypeText: String,
            isOptional: Bool,
            explicitTag: UInt32?
        )
        var raws: [Raw] = []

        for member in `struct`.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains { mod in
                mod.name.text == "static" || mod.name.text == "class"
            }
            if isStatic { continue }
            let explicit = AttributeArgumentExtractor.explicitFieldTag(of: varDecl)
            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil else { continue }
                guard
                    let ident = binding.pattern.as(IdentifierPatternSyntax.self),
                    let typeAnno = binding.typeAnnotation
                else { continue }
                let (isOpt, wrapped) = AttributeArgumentExtractor.unwrapOptional(typeAnno.type)
                raws.append((
                    name: ident.identifier.text,
                    typeText: typeAnno.type.trimmedDescription,
                    wrappedTypeText: wrapped,
                    isOptional: isOpt,
                    explicitTag: explicit,
                ))
            }
        }

        var explicitTags = Set<UInt32>()
        for raw in raws {
            if let tag = raw.explicitTag, tag != 0 {
                explicitTags.insert(tag)
            }
        }

        var counter: UInt32 = 1
        var out: [WireField] = []
        for raw in raws {
            let tag: UInt32
            if let explicit = raw.explicitTag {
                tag = explicit
            } else {
                while counter == 0
                    || reservedTags.contains(counter)
                    || explicitTags.contains(counter)
                {
                    counter &+= 1
                }
                tag = counter
                counter &+= 1
            }
            out.append(WireField(
                name: raw.name,
                typeText: raw.typeText,
                wrappedTypeText: raw.wrappedTypeText,
                isOptional: raw.isOptional,
                tag: tag,
            ))
        }
        return out
    }
}
