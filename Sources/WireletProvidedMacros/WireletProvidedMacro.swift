import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Diagnostic-only peer macro. Validates that `@WireletProvided` is applied
/// to a protocol. No Swift code is emitted — the Swift proxy and Kotlin
/// interface/adapter are generated offline by the Phase 2/3 CLIs, exactly
/// as the `@WireletObservable` JNI bridges are.
public struct WireletProvidedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: WireletProvidedDiagnostic.notAProtocol
            ))
            return []
        }
        return []
    }
}
