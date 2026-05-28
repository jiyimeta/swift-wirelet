import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct WireletObservableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasFinalModifier(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.notAFinalClass))
            return []
        }
        guard hasObservableAttribute(classDecl) else {
            context.diagnose(Diagnostic(node: Syntax(classDecl.name), message: WireletObservableDiagnostic.missingObservableAttribute))
            return []
        }
        // TODO Task 10+: emit JNI bridges per stored property.
        let body: DeclSyntax = """
        extension \(type.trimmed) {
            #if os(Android)
            // Empty until Task 10 fills in per-property expansion.
            #endif
        }
        """
        guard let ext = body.as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    private static func hasFinalModifier(_ decl: ClassDeclSyntax) -> Bool {
        decl.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
    }

    private static func hasObservableAttribute(_ decl: ClassDeclSyntax) -> Bool {
        decl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "Observable"
        }
    }
}
