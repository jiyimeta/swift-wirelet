import Foundation
import SwiftParser
import SwiftSyntax

public enum ProvidedSchemaParser {
    /// Parses the `@WireletProvided` protocols declared in a Swift source
    /// file. Declarations that are not protocols, or protocols lacking the
    /// attribute, are silently skipped.
    public static func parse(source: String, fileName: String) -> ProvidedSchema {
        let tree = Parser.parse(source: source)
        let visitor = ProvidedVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return ProvidedSchema(services: visitor.services)
    }
}

final class ProvidedVisitor: SyntaxVisitor {
    var services: [ProvidedService] = []

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasAttribute(node.attributes, named: "WireletProvided") else {
            return .visitChildren
        }
        let methods = collectMethods(of: node)
        services.append(ProvidedService(name: node.name.text, methods: methods))
        return .visitChildren
    }

    private func collectMethods(of proto: ProtocolDeclSyntax) -> [ProvidedMethod] {
        var out: [ProvidedMethod] = []
        for member in proto.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            let params = funcDecl.signature.parameterClause.parameters.map { param in
                ProvidedParameter(
                    label: param.firstName.text,
                    internalName: param.secondName?.text,
                    typeText: param.type.trimmedDescription,
                )
            }
            let returnTypeText = funcDecl.signature.returnClause?.type.trimmedDescription
            out.append(ProvidedMethod(
                name: funcDecl.name.text,
                parameters: params,
                returnTypeText: returnTypeText,
            ))
        }
        return out
    }

    private func hasAttribute(_ list: AttributeListSyntax, named name: String) -> Bool {
        for element in list {
            guard let attr = element.as(AttributeSyntax.self) else { continue }
            if attr.attributeName.trimmedDescription == name { return true }
        }
        return false
    }
}
