import WireletKotlinEmitter
import WireletObservableSchema

public struct ObservableKotlinEmitter: Sendable {
    public let config: ObservableCodegenConfig

    public init(config: ObservableCodegenConfig) {
        self.config = config
    }

    /// Renders one `<KotlinName>ViewModel.kt` file per view-model in the
    /// schema. Returns an empty list when the schema has no view-models.
    public func emit(schema: ObservableSchema) -> [KotlinFile] {
        schema.viewModels.map { vm in
            ViewModelEmitter.emit(vm, config: config)
        }
    }
}
