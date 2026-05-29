import Foundation
import Testing
@testable import WireletObservableKotlinEmitter
import WireletKotlinEmitter
import WireletObservableSchema

private func makeTestConfig() -> ObservableCodegenConfig {
    ObservableCodegenConfig(
        viewModelPackage: "com.example.app.viewmodels",
        modelPackage: "com.example.app.model",
        codecPackage: "com.example.app.codecs",
        libraryName: "ExampleJNI",
        nameTransform: .identity
    )
}

@Suite struct ViewModelEmitterTests {
    @Test func multiArgInvokeEmission() throws {
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
            ]
        )
        let output = ViewModelEmitter.emit(vm, config: makeTestConfig()).content
        #expect(output.contains("fun setDone(arg0: Int, arg1: Boolean) ="))
        #expect(output.contains("nativeSetDone(nativePtr, arg0, arg1)"))
        #expect(output.contains("private external fun nativeSetDone(self: Long, arg0: Int, arg1: Boolean)"))
    }
}
