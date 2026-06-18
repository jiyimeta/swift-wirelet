import Foundation
import Testing
@testable import WireletProvidedSchema

@Test func parsesTodoStoreService() throws {
    let url = try #require(Bundle.module.url(
        forResource: "TodoStoreService",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ProvidedSchemaParser.parse(source: source, fileName: "TodoStoreService.swift")

    #expect(schema.services.count == 1)
    let service = schema.services[0]
    #expect(service.name == "TodoStore")
    #expect(service.methods == [
        ProvidedMethod(name: "loadAll", parameters: [], returnTypeText: "[TodoItem]"),
        ProvidedMethod(
            name: "add",
            parameters: [ProvidedParameter(label: "_", internalName: "item", typeText: "TodoItem")],
            returnTypeText: nil,
        ),
        ProvidedMethod(
            name: "remove",
            parameters: [ProvidedParameter(label: "_", internalName: "id", typeText: "Int32")],
            returnTypeText: nil,
        ),
    ])
}

@Test func ignoresNonProvidedDecls() throws {
    let url = try #require(Bundle.module.url(
        forResource: "MixedDecls",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ProvidedSchemaParser.parse(source: source, fileName: "MixedDecls.swift")

    #expect(schema.services.isEmpty)
}
