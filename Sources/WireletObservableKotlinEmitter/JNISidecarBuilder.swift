import Foundation
import WireletObservableSchema

// MARK: - JNI sidecar JSON types
//
// These types mirror the `JNIRegistrationConfig` / `ViewModelRegistration` /
// `NativeMethod` types defined in `WireletObservableSwiftBridgesEmitter`. They
// are kept here so `EmitWireletObservable` (which already imports this module)
// can write the sidecar without depending on the Swift-bridges emitter target.
//
// Both definitions must stay in sync — a JSON sidecar written by one must be
// readable by the other. Field names are the coding keys; they match exactly.

public struct JNISidecar: Codable {
    public var viewModels: [JNISidecarViewModel]
    public init(viewModels: [JNISidecarViewModel]) {
        self.viewModels = viewModels
    }
}

public struct JNISidecarViewModel: Codable {
    public var swiftClass: String
    public var kotlinClassFQN: String
    public var nativeMethods: [JNISidecarNativeMethod]
    public init(swiftClass: String, kotlinClassFQN: String, nativeMethods: [JNISidecarNativeMethod]) {
        self.swiftClass = swiftClass
        self.kotlinClassFQN = kotlinClassFQN
        self.nativeMethods = nativeMethods
    }
}

public struct JNISidecarNativeMethod: Codable {
    public var name: String
    public var signature: String
    public var cdeclSymbol: String
    public init(name: String, signature: String, cdeclSymbol: String) {
        self.name = name
        self.signature = signature
        self.cdeclSymbol = cdeclSymbol
    }
}

// MARK: - Builder

/// Computes the `.wirelet-observable-jni.json` sidecar payload for a schema.
///
/// The sidecar is written by the `emit-wirelet-observable` CLI alongside the
/// Kotlin ViewModel files so the `WireletObservableBridges` SwiftPM build tool
/// plugin can instruct the Swift bridges emitter to emit a `JNI_OnLoad`.
public enum JNISidecarBuilder {
    /// Builds the sidecar for every view-model in `schema` given `config`.
    ///
    /// The Kotlin FQN uses slashes (JNI internal name), not dots. The method
    /// list mirrors the `external fun nativeXxx` declarations that
    /// `ViewModelEmitter` emits — keeping both in sync is important for
    /// correct `RegisterNatives` mappings.
    public static func build(
        schema: ObservableSchema,
        config: ObservableCodegenConfig
    ) -> JNISidecar {
        let vms = schema.viewModels.map { vm in
            buildViewModel(vm, config: config)
        }
        return JNISidecar(viewModels: vms)
    }

    // MARK: - Per-view-model

    private static func buildViewModel(
        _ vm: ObservableViewModel,
        config: ObservableCodegenConfig
    ) -> JNISidecarViewModel {
        let kotlinBase = config.nameTransform.apply(to: vm.name)
        let kotlinClassName = "\(kotlinBase)ViewModel"
        // JNI internal name: package dots → slashes
        let fqn = config.viewModelPackage.replacingOccurrences(of: ".", with: "/")
            + "/" + kotlinClassName

        var methods: [JNISidecarNativeMethod] = []

        // 1. constructor (companion object static method — still uses class lookup)
        methods.append(JNISidecarNativeMethod(
            name: "nativeNew",
            signature: "()J",
            cdeclSymbol: "WireletObservable_\(vm.name)_new"
        ))

        // 2. track methods (one per property)
        for property in vm.properties {
            let plan = ObservableKotlinTypeMap.plan(for: property, config: config)
            let nativeName = "native\(capitalised(property.name))Track"
            let sig = trackSignature(nativeTrackReturn: plan.nativeTrackReturn)
            methods.append(JNISidecarNativeMethod(
                name: nativeName,
                signature: sig,
                cdeclSymbol: "WireletObservable_\(vm.name)_\(property.name)_track"
            ))
        }

        // 3. setter methods (mutable properties only)
        for property in vm.properties where property.isMutable {
            let plan = ObservableKotlinTypeMap.plan(for: property, config: config)
            guard let setParam = plan.nativeSetParam else { continue }
            let nativeName = "native\(capitalised(property.name))Set"
            let sig = setterSignature(nativeSetParam: setParam)
            methods.append(JNISidecarNativeMethod(
                name: nativeName,
                signature: sig,
                cdeclSymbol: "WireletObservable_\(vm.name)_\(property.name)_set"
            ))
        }

        // 4. method invoke bridges
        for method in vm.methods {
            guard let entry = methodEntry(method: method, vmName: vm.name, config: config) else {
                continue
            }
            methods.append(entry)
        }

        // 5. destructor
        methods.append(JNISidecarNativeMethod(
            name: "nativeRelease",
            signature: "(J)V",
            cdeclSymbol: "WireletObservable_\(vm.name)_release"
        ))

        return JNISidecarViewModel(
            swiftClass: vm.name,
            kotlinClassFQN: fqn,
            nativeMethods: methods
        )
    }

    // MARK: - JNI signature derivation

    /// `(JLjava/lang/Runnable;)<returnDescriptor>` where returnDescriptor
    /// comes from the Kotlin track return type.
    private static func trackSignature(nativeTrackReturn: String) -> String {
        let ret = jniDescriptor(kotlinType: nativeTrackReturn)
        return "(JLjava/lang/Runnable;)\(ret)"
    }

    /// `(J<paramDescriptor>)V` where paramDescriptor comes from the Kotlin
    /// setter parameter type.
    private static func setterSignature(nativeSetParam: String) -> String {
        let param = jniDescriptor(kotlinType: nativeSetParam)
        return "(J\(param))V"
    }

    private static func methodEntry(
        method: ObservableMethod,
        vmName: String,
        config: ObservableCodegenConfig
    ) -> JNISidecarNativeMethod? {
        let nativeName = "native\(capitalised(method.name))"
        let cdecl = "WireletObservable_\(vmName)_\(method.name)_invoke"
        let argDescriptors = method.parameters
            .map { jniArgDescriptor(forArgType: $0.typeText) }
            .joined()
        return JNISidecarNativeMethod(
            name: nativeName,
            signature: "(J\(argDescriptors))V",
            cdeclSymbol: cdecl
        )
    }

    /// JNI type descriptor for one method-arg type (no `J` self prefix, no return type).
    private static func jniArgDescriptor(forArgType swiftType: String) -> String {
        switch InvokeArgClassifier.classify(swiftType) {
        case .primitive(let jniSwiftType, _):
            switch jniSwiftType {
            case "jint":     return "I"
            case "jlong":    return "J"
            case "jfloat":   return "F"
            case "jdouble":  return "D"
            case "jboolean": return "Z"
            default: return "[B"
            }
        case .bool:                                  return "Z"
        case .string, .optionalString:               return "Ljava/lang/String;"
        case .wireFormat,
             .optionalPrimitive,
             .optionalWireFormat,
             .array:
            return "[B"
        }
    }

    // MARK: - JNI type descriptor mapping

    /// Maps a Kotlin type string (as used in `external fun` declarations) to
    /// its JNI type descriptor character/string.
    private static func jniDescriptor(kotlinType: String) -> String {
        // Strip nullable suffix for descriptor lookup
        let base = kotlinType.hasSuffix("?") ? String(kotlinType.dropLast()) : kotlinType
        switch base {
        case "Boolean": return "Z"
        case "Byte":    return "B"
        case "Char":    return "C"
        case "Short":   return "S"
        case "Int":     return "I"
        case "Long":    return "J"
        case "Float":   return "F"
        case "Double":  return "D"
        case "Void", "Unit": return "V"
        case "ByteArray": return "[B"
        case "String":  return "Ljava/lang/String;"
        default:
            // For nullable variants and other types, fall back to ByteArray
            // (all Optional primitive and Optional wireformat types are
            //  transported as ByteArray? in our protocol).
            if kotlinType.hasSuffix("?") {
                // Optional primitive / Optional WireFormat → ByteArray?
                return "[B"
            }
            return "[B"
        }
    }

    private static func capitalised(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
