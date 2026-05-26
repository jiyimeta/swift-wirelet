import SwiftSyntax
import SwiftSyntaxMacros

/// Marker peer macro for `@WireFormatField(tag:)`. The expansion emits no
/// peer declarations — the enclosing `@WireFormat` extension macro reads
/// the `tag:` argument by walking the property's attribute list when
/// assigning tags.
public struct WireFormatFieldMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        []
    }
}
