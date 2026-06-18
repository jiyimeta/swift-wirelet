import SwiftDiagnostics

enum WireletObservableDiagnostic: String, DiagnosticMessage {
    case notAFinalClass
    case missingObservableAttribute
    case unsupportedPropertyType
    case unsupportedExposedMethodSignature

    var diagnosticID: MessageID {
        MessageID(domain: "WireletObservable", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        .error
    }

    var message: String {
        switch self {
        case .notAFinalClass:
            return "@WireletObservable requires a final class."
        case .missingObservableAttribute:
            return "@WireletObservable must be paired with @Observable."
        case .unsupportedPropertyType:
            let supported = "Use a primitive, String, @WireFormat type, or Optional/Array thereof."
            return "Unsupported property type for @WireletObservable. \(supported)"
        case .unsupportedExposedMethodSignature:
            let supported = "a primitive, String, @WireFormat type, or Optional / Array thereof."
            return "@WireletExpose method parameter must be \(supported)"
        }
    }
}
