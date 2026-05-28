import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WireletObservablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WireletExposeMacro.self,
        // WireletObservableMacro.self — added in Task 8.
    ]
}
