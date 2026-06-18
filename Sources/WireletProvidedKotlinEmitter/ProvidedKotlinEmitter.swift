import WireletKotlinEmitter // KotlinFile
import WireletProvidedSchema // ProvidedSchema

/// Errors surfaced while rendering a `@WireletProvided` Kotlin bridge.
public enum ProvidedKotlinEmitterError: Error, Equatable {
    /// A parameter or return type is not representable by the v1 emitter.
    /// Optionals (`T?`) are deferred; every other shape classifies via
    /// `InvokeArgClassifier`.
    case unsupportedType(service: String, method: String, type: String)
}

/// Renders one `<Service>.kt` file per `@WireletProvided` service in
/// `schema`. Each file contains a friendly `interface <Service>` and a
/// `<Service>NativeAdapter` class — the exact Kotlin dual of the Swift
/// `<Service>WireletProxy` produced by `ProvidedSwiftBridgesEmitter`.
public struct ProvidedKotlinEmitter: Sendable {
    public let config: ProvidedCodegenConfig

    public init(config: ProvidedCodegenConfig) {
        self.config = config
    }

    /// - Returns: one `KotlinFile` per discovered service.
    /// - Throws: `ProvidedKotlinEmitterError` if any method uses an
    ///   unsupported type (e.g. optionals, which are deferred to v2).
    public func emit(schema: ProvidedSchema) throws -> [KotlinFile] {
        try schema.services.map { service in
            try AdapterEmitter.emit(service: service, config: config)
        }
    }
}
