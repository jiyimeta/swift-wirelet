import SwiftDiagnostics

enum WireletProvidedDiagnostic: String, DiagnosticMessage {
    case notAProtocol

    var diagnosticID: MessageID {
        MessageID(domain: "WireletProvided", id: rawValue)
    }
    var severity: DiagnosticSeverity { .error }
    var message: String {
        switch self {
        case .notAProtocol:
            return "@WireletProvided can only be applied to a protocol."
        }
    }
}
