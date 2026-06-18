import Foundation
import SwiftParser
import SwiftSyntax

public enum ObservableSchemaParser {
    /// Parses the `@WireletObservable @Observable` view-models declared in a
    /// Swift source file. Declarations that lack either attribute or that
    /// are not classes are silently skipped — they belong to the existing
    /// wireformat emitter or are user code unrelated to this codegen.
    public static func parse(source: String, fileName: String) -> ObservableSchema {
        let tree = Parser.parse(source: source)
        let visitor = ObservableVisitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return ObservableSchema(viewModels: visitor.viewModels)
    }
}

final class ObservableVisitor: SyntaxVisitor {
    var viewModels: [ObservableViewModel] = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasAttribute(node.attributes, named: "WireletObservable") else {
            return .visitChildren
        }
        guard hasAttribute(node.attributes, named: "Observable") else {
            // Spec: only emit for classes carrying both. Bare `@WireletObservable`
            // is a macro-level diagnostic; at the schema layer we silently drop.
            return .visitChildren
        }
        let properties = collectProperties(of: node)
        let methods = collectExposedMethods(of: node)
        let initParameters = collectInitParameters(of: node)
        viewModels.append(ObservableViewModel(
            name: node.name.text,
            properties: properties,
            methods: methods,
            initParameters: initParameters,
        ))
        return .visitChildren
    }

    private func collectProperties(of classDecl: ClassDeclSyntax) -> [ObservableProperty] {
        var out: [ObservableProperty] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains { mod in
                mod.name.text == "static" || mod.name.text == "class"
            }
            if isStatic { continue }
            if hasAttribute(varDecl.attributes, named: "ObservationIgnored") { continue }
            let isMutable = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
            for binding in varDecl.bindings {
                // Computed properties (with `{ get … }`) are skipped — observation
                // only tracks stored ones.
                guard binding.accessorBlock == nil else { continue }
                guard
                    let ident = binding.pattern.as(IdentifierPatternSyntax.self),
                    let typeAnno = binding.typeAnnotation
                else { continue }
                let typeText = typeAnno.type.trimmedDescription
                guard let kind = ObservableTypeClassifier.classify(typeText) else {
                    // Unsupported property type. v0.1: silently skip; the macro layer
                    // already reports it as a build-time diagnostic, so re-reporting
                    // here would double-fire. Leaving room for a future warning-level
                    // diagnostic carried on `ObservableSchema`.
                    continue
                }
                out.append(ObservableProperty(
                    name: ident.identifier.text,
                    swiftTypeText: typeText,
                    kind: kind,
                    isMutable: isMutable,
                ))
            }
        }
        return out
    }

    private func collectExposedMethods(of classDecl: ClassDeclSyntax) -> [ObservableMethod] {
        var out: [ObservableMethod] = []
        for member in classDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard hasAttribute(funcDecl.attributes, named: "WireletExpose") else { continue }
            let params = funcDecl.signature.parameterClause.parameters.map { param in
                ObservableMethodParameter(
                    label: param.firstName.text,
                    internalName: param.secondName?.text,
                    typeText: param.type.trimmedDescription,
                )
            }
            let returnTypeText = funcDecl.signature.returnClause
                .map(\.type.trimmedDescription)
                .flatMap { $0 == "Void" || $0 == "()" ? nil : $0 }
            out.append(ObservableMethod(
                name: funcDecl.name.text,
                parameters: params,
                returnTypeText: returnTypeText,
            ))
        }
        return out
    }

    /// Captures the parameters of the class's injected initializer. v1: a
    /// single injected init. If several inits exist, the first one with a
    /// non-empty parameter clause wins; if none has parameters (only `init()`
    /// or no explicit init), returns an empty array. Raw capture only — no
    /// classification happens here.
    private func collectInitParameters(of classDecl: ClassDeclSyntax) -> [ObservableInitParameter] {
        for member in classDecl.memberBlock.members {
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { continue }
            let params = initDecl.signature.parameterClause.parameters
            guard !params.isEmpty else { continue }
            return params.map { param in
                ObservableInitParameter(
                    label: param.firstName.text,
                    internalName: param.secondName?.text,
                    typeText: param.type.trimmedDescription,
                )
            }
        }
        return []
    }

    private func hasAttribute(_ list: AttributeListSyntax, named name: String) -> Bool {
        for element in list {
            guard let attr = element.as(AttributeSyntax.self) else { continue }
            if attr.attributeName.trimmedDescription == name { return true }
        }
        return false
    }
}
