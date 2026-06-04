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

@Test func parsesInjectedInitParameters() throws {
    let source = """
    import Observation
    import WireletObservable
    @WireletObservable
    @Observable
    public final class TodoListVM {
        @ObservationIgnored let store: TodoStore
        public init(store: TodoStore) {
            self.store = store
        }
    }
    """
    let schema = ObservableSchemaParser.parse(source: source, fileName: "TodoListVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.initParameters == [
        ObservableInitParameter(label: "store", internalName: nil, typeText: "TodoStore"),
    ])
}

@Test func noArgInitYieldsEmptyInitParameters() throws {
    let source = """
    import Observation
    import WireletObservable
    @WireletObservable
    @Observable
    public final class CounterVM {
        public var count: Int32 = 0
        public init() {}
    }
    """
    let schema = ObservableSchemaParser.parse(source: source, fileName: "CounterVM.swift")

    #expect(schema.viewModels.count == 1)
    #expect(schema.viewModels[0].initParameters == [])
}

@Test func parsesMethodReturnTypes() throws {
    let source = """
    import Observation
    import WireletObservable
    @WireletObservable
    @Observable
    public final class ReturnsVM {
        @WireletExpose public func foo(_ a: String) -> String { a }
        @WireletExpose public func bar() {}
        @WireletExpose public func baz() -> Void {}
        @WireletExpose public func qux() -> () {}
        @WireletExpose public func items() -> [TodoItem] { [] }
    }
    """
    let schema = ObservableSchemaParser.parse(source: source, fileName: "ReturnsVM.swift")

    #expect(schema.viewModels.count == 1)
    let vm = schema.viewModels[0]
    #expect(vm.methods == [
        ObservableMethod(
            name: "foo",
            parameters: [
                ObservableMethodParameter(label: "_", internalName: "a", typeText: "String"),
            ],
            returnTypeText: "String"
        ),
        ObservableMethod(name: "bar", parameters: [], returnTypeText: nil),
        ObservableMethod(name: "baz", parameters: [], returnTypeText: nil),
        ObservableMethod(name: "qux", parameters: [], returnTypeText: nil),
        ObservableMethod(name: "items", parameters: [], returnTypeText: "[TodoItem]"),
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
