import SwiftDiagnostics

enum WireFormatDiagnostic: DiagnosticMessage {
    case notAStruct
    case notAnEnum
    case missingTypeAnnotation(propertyName: String)
    case missingRawType

    var message: String {
        switch self {
        case .notAStruct:
            return "@WireFormat can only be applied to a struct"
        case .notAnEnum:
            return "@WireFormatEnum can only be applied to an enum"
        case let .missingTypeAnnotation(name):
            return "@WireFormat requires an explicit type annotation on stored property '\(name)'"
        case .missingRawType:
            return "@WireFormatEnum requires the enum to declare a raw type (e.g. ': UInt8' or ': String')"
        }
    }

    var diagnosticID: MessageID {
        let id: String
        switch self {
        case .notAStruct: id = "notAStruct"
        case .notAnEnum: id = "notAnEnum"
        case .missingTypeAnnotation: id = "missingTypeAnnotation"
        case .missingRawType: id = "missingRawType"
        }
        return MessageID(domain: "Wirelet", id: id)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
