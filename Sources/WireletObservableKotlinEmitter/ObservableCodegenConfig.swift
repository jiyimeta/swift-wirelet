import Foundation
import WireletKotlinEmitter

/// JSON-decodable config for `emit-wirelet-observable`. Mirrors
/// `KotlinCodegenConfig` (Sources/WireletKotlinEmitter/KotlinCodegenConfig.swift:3)
/// but carries the observable-specific packages and JNI library name.
public struct ObservableCodegenConfig: Codable, Sendable, Equatable {
    /// Package the generated `<Name>ViewModel.kt` files land in.
    public var viewModelPackage: String
    /// Package the user-authored model classes (`TodoItem`, etc.) live in.
    /// Used to render `import <modelPackage>.<TypeName>` for every referenced
    /// `@WireFormat` user type.
    public var modelPackage: String
    /// Package the wireformat codecs live in. Used to render
    /// `import <codecPackage>.<TypeName>Codec` for setter/expose decoding
    /// and array decoding.
    public var codecPackage: String
    /// Package the `wirelet-observable-runtime` artifact exposes
    /// `WireletList` from. Defaults to
    /// `io.github.jiyimeta.wirelet.observable` per Phase 3's runtime
    /// package layout (spec line 244–249).
    public var runtimePackage: String
    /// `System.loadLibrary` argument. The consumer's Swift package, when
    /// cross-compiled to `aarch64-unknown-linux-android28`, produces a
    /// `lib<name>.so`; this string is `<name>`.
    public var libraryName: String
    /// Applied to the Swift class name before suffixing with `ViewModel`
    /// (e.g. `stripSuffix: "VM"` so `TodoListVM` → `TodoListViewModel`).
    /// Defaults to `identity` per the existing wireformat config.
    public var nameTransform: NameTransform

    public init(
        viewModelPackage: String,
        modelPackage: String,
        codecPackage: String,
        runtimePackage: String = "io.github.jiyimeta.wirelet.observable",
        libraryName: String,
        nameTransform: NameTransform = .identity
    ) {
        self.viewModelPackage = viewModelPackage
        self.modelPackage = modelPackage
        self.codecPackage = codecPackage
        self.runtimePackage = runtimePackage
        self.libraryName = libraryName
        self.nameTransform = nameTransform
    }

    private enum CodingKeys: String, CodingKey {
        case viewModelPackage
        case modelPackage
        case codecPackage
        case runtimePackage
        case libraryName
        case nameTransform
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewModelPackage = try c.decode(String.self, forKey: .viewModelPackage)
        modelPackage = try c.decode(String.self, forKey: .modelPackage)
        codecPackage = try c.decode(String.self, forKey: .codecPackage)
        runtimePackage = try c.decodeIfPresent(String.self, forKey: .runtimePackage)
            ?? "io.github.jiyimeta.wirelet.observable"
        libraryName = try c.decode(String.self, forKey: .libraryName)
        nameTransform = try c.decodeIfPresent(NameTransform.self, forKey: .nameTransform)
            ?? .identity
    }
}
