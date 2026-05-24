import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireFormatMacro.self,
        WireFormatEnumMacro.self,
        WireFormatChoiceMacro.self,
    ]
}
