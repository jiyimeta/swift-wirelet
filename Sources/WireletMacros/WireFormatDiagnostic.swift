import SwiftDiagnostics

enum WireFormatDiagnostic: DiagnosticMessage {
    case notAStruct
    case notAnEnum
    case missingTypeAnnotation(propertyName: String)
    case missingRawType
    case tagConflict(tag: UInt32)
    case reservedTagUsed(tag: UInt32, fieldName: String)
    case tagOutOfRange(fieldName: String)
    case choiceWithoutAssociatedValues
    case fieldOnComputedProperty(propertyName: String)

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
        case let .tagConflict(tag):
            return "Tag \(tag) is used by multiple fields"
        case let .reservedTagUsed(tag, name):
            return "Tag \(tag) is reserved and cannot be used by field '\(name)'"
        case let .tagOutOfRange(name):
            return "Field '\(name)' has explicit tag 0; tags must be > 0"
        case .choiceWithoutAssociatedValues:
            return "@WireFormatChoice expects at least one case with associated values; prefer @WireFormatEnum for plain enums"
        case let .fieldOnComputedProperty(name):
            return "@WireFormatField is ignored on computed property '\(name)'"
        }
    }

    var diagnosticID: MessageID {
        let id: String
        switch self {
        case .notAStruct: id = "notAStruct"
        case .notAnEnum: id = "notAnEnum"
        case .missingTypeAnnotation: id = "missingTypeAnnotation"
        case .missingRawType: id = "missingRawType"
        case .tagConflict: id = "tagConflict"
        case .reservedTagUsed: id = "reservedTagUsed"
        case .tagOutOfRange: id = "tagOutOfRange"
        case .choiceWithoutAssociatedValues: id = "choiceWithoutAssociatedValues"
        case .fieldOnComputedProperty: id = "fieldOnComputedProperty"
        }
        return MessageID(domain: "Wirelet", id: id)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .choiceWithoutAssociatedValues, .fieldOnComputedProperty:
            return .warning
        case .notAStruct, .notAnEnum, .missingTypeAnnotation, .missingRawType,
             .tagConflict, .reservedTagUsed, .tagOutOfRange:
            return .error
        }
    }
}
