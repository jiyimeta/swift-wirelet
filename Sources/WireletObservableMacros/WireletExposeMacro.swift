import SwiftSyntax
import SwiftSyntaxMacros

/// Marker attribute. The schema parser inspects functions carrying this
/// attribute; the macro itself synthesizes nothing.
public struct WireletExposeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
