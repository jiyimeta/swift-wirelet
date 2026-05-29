import Foundation
import Testing
@testable import WireletObservableSchema

@Test func parsesCounterVM() throws {
    let url = try #require(Bundle.module.url(
        forResource: "CounterVM",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "CounterVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.name == "CounterVM")
    #expect(vm.properties == [
        ObservableProperty(
            name: "count",
            swiftTypeText: "Int32",
            kind: .primitive,
            isMutable: true
        ),
    ])
    #expect(vm.methods == [
        ObservableMethod(name: "increment", parameters: []),
    ])
}

@Test func parsesTodoListVM() throws {
    let url = try #require(Bundle.module.url(
        forResource: "TodoListVM",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "TodoListVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.name == "TodoListVM")

    // configKey is static → skipped. debugLabel is @ObservationIgnored → skipped.
    // unmarkedHelper has no @WireletExpose → not in methods.
    #expect(vm.properties == [
        ObservableProperty(
            name: "items",
            swiftTypeText: "[TodoItem]",
            kind: .wireFormatArray(elementTypeName: "TodoItem"),
            isMutable: true
        ),
        ObservableProperty(
            name: "filter",
            swiftTypeText: "String",
            kind: .string,
            isMutable: true
        ),
        ObservableProperty(
            name: "totalCount",
            swiftTypeText: "Int32",
            kind: .primitive,
            isMutable: true
        ),
        ObservableProperty(
            name: "pinned",
            swiftTypeText: "TodoItem?",
            kind: .optionalWireFormat(typeName: "TodoItem"),
            isMutable: true
        ),
    ])
    #expect(vm.methods == [
        ObservableMethod(name: "add", parameters: [
            ObservableMethodParameter(label: "_", internalName: "item", typeText: "TodoItem"),
        ]),
        ObservableMethod(name: "clear", parameters: []),
    ])
}

@Test func ignoresNonObservableDecls() throws {
    let url = try #require(Bundle.module.url(
        forResource: "MixedDecls",
        withExtension: "swift",
        subdirectory: "Fixtures"
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = ObservableSchemaParser.parse(source: source, fileName: "MixedDecls.swift")

    #expect(schema.viewModels.isEmpty)
}
