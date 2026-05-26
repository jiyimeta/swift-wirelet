import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireFormatMacro.self,
        WireFormatFieldMacro.self,
        WireFormatEnumMacro.self,
        WireFormatChoiceMacro.self,
    ]
}
