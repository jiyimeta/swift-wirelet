import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletProvidedMacros

private let macroSpecs: [String: any Macro.Type] = [
    "WireletProvided": WireletProvidedMacro.self,
]

final class WireletProvidedMacroTests: XCTestCase {
    func testProtocolExpandsToItselfWithNoPeers() {
        assertMacroExpansion(
            """
            @WireletProvided
            protocol TodoStore {
                func loadAll() -> [TodoItem]
                func add(_ item: TodoItem)
            }
            """,
            expandedSource: """
            protocol TodoStore {
                func loadAll() -> [TodoItem]
                func add(_ item: TodoItem)
            }
            """,
            macros: macroSpecs
        )
    }

    func testNonProtocolEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletProvided
            struct NotAProtocol {
            }
            """,
            expandedSource: """
            struct NotAProtocol {
            }
            """,
            diagnostics: [
                .init(message: "@WireletProvided can only be applied to a protocol.", line: 1, column: 1),
            ],
            macros: macroSpecs
        )
    }
}
