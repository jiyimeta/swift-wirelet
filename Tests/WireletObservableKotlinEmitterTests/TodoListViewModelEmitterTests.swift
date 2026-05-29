import Foundation
import Testing
@testable import WireletObservableKotlinEmitter
import WireletKotlinEmitter
import WireletObservableSchema

@Test func emitsTodoListViewModel() throws {
    let vm = ObservableViewModel(
        name: "TodoListVM",
        properties: [
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
        ],
        methods: [
            ObservableMethod(name: "add", parameters: [
                ObservableMethodParameter(label: "_", internalName: "item", typeText: "TodoItem"),
            ]),
            ObservableMethod(name: "clear", parameters: []),
        ]
    )
    let config = ObservableCodegenConfig(
        viewModelPackage: "io.github.jiyimeta.observablecounter.generated",
        modelPackage: "io.github.jiyimeta.observablecounter",
        codecPackage: "io.github.jiyimeta.observablecounter.codecs",
        libraryName: "ObservableCounterJNI",
        nameTransform: .stripSuffix("VM")
    )

    let files = ObservableKotlinEmitter(config: config)
        .emit(schema: ObservableSchema(viewModels: [vm]))

    #expect(files.count == 1)
    let actual = try #require(files.first)
    #expect(actual.relativePath ==
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt")

    let url = try #require(Bundle.module.url(
        forResource: "TodoListViewModel.expected",
        withExtension: "kt",
        subdirectory: "Fixtures"
    ))
    let expected = try String(contentsOf: url, encoding: .utf8)
    if actual.content != expected {
        try? actual.content.write(
            toFile: "/tmp/TodoListViewModel.actual.kt",
            atomically: true,
            encoding: .utf8
        )
        Issue.record("""
        Golden mismatch. Actual written to /tmp/TodoListViewModel.actual.kt.
        Copy it into Fixtures/TodoListViewModel.expected.kt once the shape is verified.
        """)
    }
}
