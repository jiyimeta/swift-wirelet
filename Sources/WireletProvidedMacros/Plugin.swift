import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletProvidedPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireletProvidedMacro.self,
    ]
}
