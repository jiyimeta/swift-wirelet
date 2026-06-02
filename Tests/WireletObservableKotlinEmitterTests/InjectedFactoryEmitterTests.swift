import Foundation
import Testing
@testable import WireletObservableKotlinEmitter
import WireletKotlinEmitter
import WireletObservableSchema

private func makeInjectedConfig() -> ObservableCodegenConfig {
    ObservableCodegenConfig(
        viewModelPackage: "com.example.app.viewmodels",
        modelPackage: "com.example.app.model",
        codecPackage: "com.example.app.codecs",
        libraryName: "ExampleJNI",
        nameTransform: .stripSuffix("VM"),
        providedAdapterPackage: "com.example.iface"
    )
}

@Suite struct InjectedFactoryEmitterTests {
    @Test func injectedFactory() throws {
        let vm = ObservableViewModel(
            name: "TodoListVM",
            properties: [],
            methods: [],
            initParameters: [
                ObservableInitParameter(label: "store", internalName: nil, typeText: "TodoStore"),
            ]
        )
        let output = ViewModelEmitter.emit(vm, config: makeInjectedConfig()).content
        #expect(output.contains(
            "fun create(store: TodoStore): TodoListViewModel ="
        ))
        #expect(output.contains(
            "TodoListViewModel(nativeNew(TodoStoreNativeAdapter(store)))"
        ))
        #expect(output.contains(
            "private external fun nativeNew(storeAdapter: TodoStoreNativeAdapter): Long"
        ))
        #expect(output.contains("import com.example.iface.TodoStore"))
        #expect(output.contains("import com.example.iface.TodoStoreNativeAdapter"))
    }

    @Test func noArgFactoryUnchanged() throws {
        let vm = ObservableViewModel(
            name: "TodoListVM",
            properties: [],
            methods: [],
            initParameters: []
        )
        let output = ViewModelEmitter.emit(vm, config: makeInjectedConfig()).content
        #expect(output.contains("fun create(): TodoListViewModel ="))
        #expect(output.contains("TodoListViewModel(nativeNew())"))
        #expect(output.contains("private external fun nativeNew(): Long"))
        #expect(!output.contains("NativeAdapter"))
    }

    @Test func injectedFactoryColocatedFallback() throws {
        // When providedAdapterPackage is nil, the factory still wraps in the
        // adapter type but emits the type names unqualified (no import).
        var config = makeInjectedConfig()
        config.providedAdapterPackage = nil
        let vm = ObservableViewModel(
            name: "TodoListVM",
            properties: [],
            methods: [],
            initParameters: [
                ObservableInitParameter(label: "store", internalName: nil, typeText: "TodoStore"),
            ]
        )
        let output = ViewModelEmitter.emit(vm, config: config).content
        #expect(output.contains("fun create(store: TodoStore): TodoListViewModel ="))
        #expect(output.contains("TodoStoreNativeAdapter(store)"))
        #expect(!output.contains("import com.example.iface.TodoStore"))
    }
}
