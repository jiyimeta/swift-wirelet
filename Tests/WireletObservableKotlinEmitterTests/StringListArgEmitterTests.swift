import Testing
@testable import WireletObservableKotlinEmitter
import WireletObservableSchema

/// Regression guard for `[String]` (array-of-primitive) `@WireletExpose`
/// method arguments. Primitives have no generated `<Type>Codec`, so the
/// emitter must route them through the runtime's `WireletList.encodeStrings`
/// rather than referencing a fabricated `StringCodec` in the model package
/// (which does not exist and fails to compile). Verified end-to-end on a Pixel
/// by `StringListArgInstrumentedTest` in the observable-counter example.
struct StringListArgEmitterTests {
    @Test func stringArrayArgUsesEncodeStringsAndNoFabricatedCodec() throws {
        let vm = ObservableViewModel(
            name: "BulkVM",
            properties: [
                ObservableProperty(
                    name: "items",
                    swiftTypeText: "[TodoItem]",
                    kind: .wireFormatArray(elementTypeName: "TodoItem"),
                    isMutable: true,
                ),
            ],
            methods: [
                ObservableMethod(name: "addTitles", parameters: [
                    ObservableMethodParameter(label: "_", internalName: "titles", typeText: "[String]"),
                ]),
            ],
        )
        let config = ObservableCodegenConfig(
            viewModelPackage: "com.example.generated",
            modelPackage: "com.example",
            codecPackage: "com.example.codecs",
            libraryName: "ExampleJNI",
            nameTransform: .stripSuffix("VM"),
        )

        let files = ObservableKotlinEmitter(config: config)
            .emit(schema: ObservableSchema(viewModels: [vm]))
        let content = try #require(files.first?.content)

        #expect(content.contains("fun addTitles(titles: List<String>)"))
        #expect(content.contains("WireletList.encodeStrings(titles)"))
        #expect(content.contains("import io.github.jiyimeta.wirelet.observable.WireletList"))
        // No fabricated primitive codec / model import for `String`.
        #expect(!content.contains("StringCodec"))
        #expect(!content.contains("import com.example.String"))
    }
}
