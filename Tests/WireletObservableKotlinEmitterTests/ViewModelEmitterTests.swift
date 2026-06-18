import Foundation
import Testing
import WireletKotlinEmitter
@testable import WireletObservableKotlinEmitter
import WireletObservableSchema

private func makeTestConfig() -> ObservableCodegenConfig {
    ObservableCodegenConfig(
        viewModelPackage: "com.example.app.viewmodels",
        modelPackage: "com.example.app.model",
        codecPackage: "com.example.app.codecs",
        libraryName: "ExampleJNI",
        nameTransform: .identity,
    )
}

@Suite struct ViewModelEmitterTests {
    @Test func multiArgInvokeEmission() {
        let vm = ObservableViewModel(
            name: "Demo",
            properties: [],
            methods: [
                ObservableMethod(
                    name: "setDone",
                    parameters: [
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "Int32"),
                        ObservableMethodParameter(label: "_", internalName: nil, typeText: "Bool"),
                    ],
                ),
            ],
        )
        let output = ViewModelEmitter.emit(vm, config: makeTestConfig()).content
        #expect(output.contains("fun setDone(arg0: Int, arg1: Boolean) ="))
        #expect(output.contains("nativeSetDone(nativePtr, arg0, arg1)"))
        #expect(output.contains("private external fun nativeSetDone(self: Long, arg0: Int, arg1: Boolean)"))
    }

    @Test func returnTypeEmission() {
        let vm = ObservableViewModel(
            name: "Demo",
            properties: [],
            methods: [
                ObservableMethod(name: "describe", parameters: [], returnTypeText: "String"),
                ObservableMethod(name: "count", parameters: [], returnTypeText: "Int32"),
                ObservableMethod(name: "snapshot", parameters: [], returnTypeText: "[TodoItem]"),
                ObservableMethod(
                    name: "export",
                    parameters: [
                        ObservableMethodParameter(label: "_", internalName: "id", typeText: "String"),
                    ],
                    returnTypeText: "String",
                ),
                ObservableMethod(name: "noop", parameters: [], returnTypeText: nil),
            ],
        )
        let output = ViewModelEmitter.emit(vm, config: makeTestConfig()).content

        // String return: jstring → String, no decode.
        #expect(output.contains("fun describe(): String = nativeDescribe(nativePtr)"))
        #expect(output.contains("private external fun nativeDescribe(self: Long): String"))
        // Primitive return: direct.
        #expect(output.contains("fun count(): Int = nativeCount(nativePtr)"))
        #expect(output.contains("private external fun nativeCount(self: Long): Int"))
        // Wire array return: decode via WireletList + codec.
        let snapshotDecl = "fun snapshot(): List<TodoItem> = WireletList.decode("
            + "nativeSnapshot(nativePtr), TodoItemCodec::decodePayload)"
        #expect(output.contains(snapshotDecl))
        #expect(output.contains("private external fun nativeSnapshot(self: Long): ByteArray"))
        // Arg + String return.
        #expect(output.contains("fun export(id: String): String ="))
        #expect(output.contains("nativeExport(nativePtr, id)"))
        #expect(output.contains("private external fun nativeExport(self: Long, arg0: String): String"))
        // Void return unchanged.
        #expect(output.contains("fun noop() = nativeNoop(nativePtr)"))
        #expect(output.contains("private external fun nativeNoop(self: Long)"))
    }
}
