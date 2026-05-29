import Testing
@testable import WireletObservableKotlinEmitter
import WireletObservableSchema

private func makeConfig() -> ObservableCodegenConfig {
    ObservableCodegenConfig(
        viewModelPackage: "com.example.viewmodels",
        modelPackage: "com.example.model",
        codecPackage: "com.example.codecs",
        libraryName: "ExampleJNI",
        nameTransform: .identity
    )
}

@Suite struct JNISidecarBuilderTests {
    @Test func multiArgSignature() throws {
        let vm = ObservableViewModel(
            name: "Demo",
            properties: [],
            methods: [
                ObservableMethod(
                    name: "setDone",
                    parameters: [
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "Int32"),
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "Bool"),
                    ]
                ),
                ObservableMethod(
                    name: "render",
                    parameters: [
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "Int32"),
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "TodoItem"),
                    ]
                ),
            ]
        )
        let schema = ObservableSchema(viewModels: [vm])
        let config = makeConfig()
        let sidecar = JNISidecarBuilder.build(schema: schema, config: config)
        let registration = try #require(sidecar.viewModels.first)
        let setDone = try #require(registration.nativeMethods.first { $0.name == "nativeSetDone" })
        let render = try #require(registration.nativeMethods.first { $0.name == "nativeRender" })
        #expect(setDone.signature == "(JIZ)V")
        #expect(render.signature == "(JI[B)V")
    }
}
