/// Translates a Swift default value written on a `@WireFormat` field into the
/// equivalent Kotlin literal, so the emitted `data class` can carry it as a
/// parameter default.
///
/// Deliberately narrow. It accepts plain literals of the scalar types
/// `KotlinTypeMap` already knows how to carry over the wire, and nothing else:
/// no expressions, no named constants, no aggregates. Anything outside that set
/// is reported rather than dropped — a silently discarded default would put the
/// generated constructor back to requiring the parameter, which is exactly the
/// source break this metadata exists to prevent, and it would do it invisibly.
enum KotlinLiteral {
    /// Kotlin spelling of `swiftLiteral` for a field of Swift type
    /// `swiftType`, or `nil` when this translator cannot vouch for it.
    ///
    /// `swiftType` is the *wrapped* type — Optional fields already default to
    /// `null` from the type itself and never reach here.
    static func translate(swiftLiteral: String, forSwiftType swiftType: String) -> String? {
        let literal = swiftLiteral.trimmingCharactersInWhitespace()
        switch swiftType {
        case "Int8", "Int16", "Int32":
            return integerLiteral(literal).map(\.self)
        case "Int64":
            return integerLiteral(literal).map { "\($0)L" }
        case "UInt8", "UInt16", "UInt32":
            return unsignedIntegerLiteral(literal).map { "\($0)u" }
        case "UInt64":
            return unsignedIntegerLiteral(literal).map { "\($0)uL" }
        case "Float":
            return floatingPointLiteral(literal).map { "\($0)f" }
        case "Double":
            return floatingPointLiteral(literal)
        case "Bool":
            return literal == "true" || literal == "false" ? literal : nil
        case "String":
            return stringLiteral(literal)
        default:
            return nil
        }
    }

    /// A Swift integer literal, normalized (underscores removed, sign kept).
    /// Rejects hex/octal/binary rather than converting them: Kotlin spells the
    /// prefixes differently and a wrong conversion is worse than no default.
    private static func integerLiteral(_ text: String) -> String? {
        var body = Substring(text)
        var sign = ""
        if body.first == "-" || body.first == "+" {
            if body.first == "-" { sign = "-" }
            body = body.dropFirst()
        }
        let digits = String(body.filter { $0 != "_" })
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return sign + digits
    }

    /// As `integerLiteral`, but a negative value can never be an unsigned default.
    private static func unsignedIntegerLiteral(_ text: String) -> String? {
        guard let value = integerLiteral(text), !value.hasPrefix("-") else { return nil }
        return value
    }

    /// A Swift decimal floating-point literal. Kotlin needs a decimal point to
    /// read a literal as floating point, so a whole number gains `.0`.
    /// Exponent forms are rejected for the same reason hex integers are.
    private static func floatingPointLiteral(_ text: String) -> String? {
        guard let normalized = integerLiteral(text).map({ "\($0).0" }) ?? decimalLiteral(text) else {
            return nil
        }
        return normalized
    }

    private static func decimalLiteral(_ text: String) -> String? {
        var body = Substring(text)
        var sign = ""
        if body.first == "-" || body.first == "+" {
            if body.first == "-" { sign = "-" }
            body = body.dropFirst()
        }
        let cleaned = String(body.filter { $0 != "_" })
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty,
              parts[0].allSatisfy(\.isASCIIDigit), parts[1].allSatisfy(\.isASCIIDigit)
        else { return nil }
        return sign + cleaned
    }

    /// A Swift string literal. Only the plain `"…"` form, with no interpolation
    /// and no escapes whose Kotlin meaning would have to be reasoned about.
    private static func stringLiteral(_ text: String) -> String? {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return nil }
        let inner = text.dropFirst().dropLast()
        guard !inner.contains("\\"), !inner.contains("\"") else { return nil }
        return text
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

extension String {
    fileprivate func trimmingCharactersInWhitespace() -> String {
        var result = Substring(self)
        while let first = result.first, first.isWhitespace {
            result = result.dropFirst()
        }
        while let last = result.last, last.isWhitespace {
            result = result.dropLast()
        }
        return String(result)
    }
}
