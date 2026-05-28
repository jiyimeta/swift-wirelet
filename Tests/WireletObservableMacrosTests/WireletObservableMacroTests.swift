import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import WireletObservableMacros

private let macroSpecs: [String: any Macro.Type] = [
    "WireletObservable": WireletObservableMacro.self,
    "WireletExpose": WireletExposeMacro.self,
]

@Suite struct WireletObservableMacroDiagnostics {
    @Test func nonFinalClassEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable requires a final class.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }

    @Test func missingObservableEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            final class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable must be paired with @Observable.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }
}
