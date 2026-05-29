import Foundation

// MARK: - JNI registration sidecar JSON types

/// Top-level payload of the `.wirelet-observable-jni.json` sidecar file
/// written by the Wirelet Gradle plugin alongside the Swift schema sources.
/// The `WireletObservableBridges` SwiftPM build tool plugin reads this file
/// (when present) and passes its path to the CLI via `--jni-config`, which
/// then instructs `SwiftBridgesEmitter` to append a `JNI_OnLoad` function to
/// the generated output.
public struct JNIRegistrationConfig: Codable, Sendable, Equatable {
    /// One entry per `@WireletObservable` class in the schema.
    public var viewModels: [ViewModelRegistration]

    public init(viewModels: [ViewModelRegistration]) {
        self.viewModels = viewModels
    }
}

/// Describes one Kotlin ViewModel class and all its JNI-registered native
/// methods. The SwiftPM build tool plugin uses this to emit a `JNI_OnLoad`
/// that calls `RegisterNatives` for every `external fun` in the generated
/// Kotlin class.
public struct ViewModelRegistration: Codable, Sendable, Equatable {
    /// Swift class name (e.g. `TodoListVM`). Used for documentation in the
    /// emitted file but not at runtime.
    public var swiftClass: String
    /// Internal JNI class name with slashes, not dots
    /// (e.g. `io/github/jiyimeta/observablecounter/generated/TodoListVMViewModel`).
    /// Passed to `FindClass` at library load time.
    public var kotlinClassFQN: String
    /// JNI native methods that need registering via `RegisterNatives`.
    public var nativeMethods: [NativeMethod]

    public init(swiftClass: String, kotlinClassFQN: String, nativeMethods: [NativeMethod]) {
        self.swiftClass = swiftClass
        self.kotlinClassFQN = kotlinClassFQN
        self.nativeMethods = nativeMethods
    }
}

/// One row in the `JNINativeMethod` table — maps a Kotlin `external fun`
/// name + JNI signature to a Swift `@_cdecl` symbol resolved via `dlsym`.
public struct NativeMethod: Codable, Sendable, Equatable {
    /// Kotlin method name as declared (e.g. `nativeItemsTrack`).
    public var name: String
    /// JNI type descriptor string (e.g. `(JLjava/lang/Runnable;)[B`).
    public var signature: String
    /// `@_cdecl` export symbol (e.g. `WireletObservable_TodoListVM_items_track`).
    public var cdeclSymbol: String

    public init(name: String, signature: String, cdeclSymbol: String) {
        self.name = name
        self.signature = signature
        self.cdeclSymbol = cdeclSymbol
    }
}
