import Foundation
import WireletKotlinEmitter // NameTransform

/// JSON-decodable config for `emit-wirelet-provided`. Mirrors
/// `ObservableCodegenConfig` but carries the provided-bridge-specific
/// packages. The CLI in Phase 4 loads this from a JSON file.
public struct ProvidedCodegenConfig: Codable, Sendable, Equatable {
    /// Package the generated `<Name>.kt` interface + adapter files land in.
    /// v1 colocates interface and adapter in the same package (see
    /// `AdapterEmitter`).
    public var interfacePackage: String
    /// Package where the adapter class would land in a future split-file
    /// layout. Currently unused by the renderer (v1 colocates) but kept in
    /// config for forward-compatibility with Phase 4's CLI.
    public var adapterPackage: String
    /// Package the user-authored model classes (`TodoItem`, etc.) live in.
    /// Used to render `import <modelPackage>.<TypeName>`.
    public var modelPackage: String
    /// Package the wireformat codecs live in. Used to render
    /// `import <codecPackage>.<TypeName>Codec`.
    public var codecPackage: String
    /// Package the `wirelet-observable-runtime` artifact exposes
    /// `WireletList` from. Defaults to
    /// `io.github.jiyimeta.wirelet.observable`.
    public var runtimePackage: String

    public init(
        interfacePackage: String,
        adapterPackage: String,
        modelPackage: String,
        codecPackage: String,
        runtimePackage: String = "io.github.jiyimeta.wirelet.observable",
    ) {
        self.interfacePackage = interfacePackage
        self.adapterPackage = adapterPackage
        self.modelPackage = modelPackage
        self.codecPackage = codecPackage
        self.runtimePackage = runtimePackage
    }

    private enum CodingKeys: String, CodingKey {
        case interfacePackage
        case adapterPackage
        case modelPackage
        case codecPackage
        case runtimePackage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interfacePackage = try c.decode(String.self, forKey: .interfacePackage)
        adapterPackage = try c.decode(String.self, forKey: .adapterPackage)
        modelPackage = try c.decode(String.self, forKey: .modelPackage)
        codecPackage = try c.decode(String.self, forKey: .codecPackage)
        runtimePackage = try c.decodeIfPresent(String.self, forKey: .runtimePackage)
            ?? "io.github.jiyimeta.wirelet.observable"
    }
}
