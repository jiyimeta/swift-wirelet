import WireletSchema

enum KotlinTypeMap {
    /// Plan for emitting one TLV field whose Swift type maps to a Kotlin
    /// primitive. The emitter uses these to render `writeTag` + payload
    /// snippets on the encode side and the per-tag case body on the
    /// decode side.
    struct Primitive {
        /// Kotlin spelling of the type (e.g. `Int`, `Long`, `Boolean`,
        /// `ByteArray`).
        let kotlinType: String
        /// `WireType.<NAME>` constant used in the tag header.
        let wireType: String
        /// Renders the payload-write expression for `value` (no tag, no
        /// outer length-prefix wrap — but writes its own length where the
        /// payload requires it, e.g. for String / Data).
        let writePayload: (_ valueExpr: String, _ writerName: String) -> String
        /// Renders the payload-read expression that yields the Kotlin
        /// value from `<readerName>`.
        let readPayload: (_ readerName: String) -> String
    }

    /// Returns the TLV plan for a Swift primitive type, or `nil` for
    /// non-primitive (structured / user-defined) types.
    static func primitive(_ swiftType: String) -> Primitive? {
        integerPrimitive(swiftType) ?? scalarPrimitive(swiftType)
    }

    private static func integerPrimitive(_ swiftType: String) -> Primitive? {
        switch swiftType {
        case "Int8":
            return Primitive(
                kotlinType: "Byte",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeZigZagVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readZigZagVarint().toByte()" },
            )
        case "Int16":
            return Primitive(
                kotlinType: "Short",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeZigZagVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readZigZagVarint().toShort()" },
            )
        case "Int32":
            return Primitive(
                kotlinType: "Int",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeZigZagVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readZigZagVarint().toInt()" },
            )
        case "Int64":
            return Primitive(
                kotlinType: "Long",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeZigZagVarint(\(v))" },
                readPayload: { r in "\(r).readZigZagVarint()" },
            )
        case "UInt8":
            return Primitive(
                kotlinType: "UByte",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readVarint().toUByte()" },
            )
        case "UInt16":
            return Primitive(
                kotlinType: "UShort",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readVarint().toUShort()" },
            )
        case "UInt32":
            return Primitive(
                kotlinType: "UInt",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readVarint().toUInt()" },
            )
        case "UInt64":
            return Primitive(
                kotlinType: "ULong",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeVarint((\(v)).toLong())" },
                readPayload: { r in "\(r).readVarint().toULong()" },
            )
        default:
            return nil
        }
    }

    private static func scalarPrimitive(_ swiftType: String) -> Primitive? {
        switch swiftType {
        case "Float":
            return Primitive(
                kotlinType: "Float",
                wireType: "WireType.FIXED32",
                writePayload: { v, w in "\(w).writeF32(\(v))" },
                readPayload: { r in "\(r).readF32()" },
            )
        case "Double":
            return Primitive(
                kotlinType: "Double",
                wireType: "WireType.FIXED64",
                writePayload: { v, w in "\(w).writeF64(\(v))" },
                readPayload: { r in "\(r).readF64()" },
            )
        case "Bool":
            return Primitive(
                kotlinType: "Boolean",
                wireType: "WireType.VARINT",
                writePayload: { v, w in "\(w).writeVarint(if (\(v)) 1L else 0L)" },
                readPayload: { r in "\(r).readVarint() != 0L" },
            )
        case "String":
            return Primitive(
                kotlinType: "String",
                wireType: "WireType.LENGTH_DELIMITED",
                writePayload: { v, w in
                    "\(w).writeLengthPrefixed { writeBytes((\(v)).toByteArray(Charsets.UTF_8)) }"
                },
                readPayload: { r in
                    "\(r).readLengthPrefixed { it.readBytes(it.remaining).toString(Charsets.UTF_8) }"
                },
            )
        case "Data":
            return Primitive(
                kotlinType: "ByteArray",
                wireType: "WireType.LENGTH_DELIMITED",
                writePayload: { v, w in
                    "\(w).writeLengthPrefixed { writeBytes(\(v)) }"
                },
                readPayload: { r in
                    "\(r).readLengthPrefixed { it.readBytes(it.remaining) }"
                },
            )
        default:
            return nil
        }
    }

    /// Strips a Swift nested-type prefix (`Outer.Inner` → `Inner`). Codecs
    /// and model classes are emitted at top level, so namespace-qualified
    /// references in field / payload type text must be flattened before
    /// they become codec object names or import targets.
    static func simpleName(of typeText: String) -> String {
        guard let lastDot = typeText.lastIndex(of: ".") else { return typeText }
        return String(typeText[typeText.index(after: lastDot)...])
    }

    /// Returns the element type for an `[T]` (sugared array) type text, or
    /// `nil` for any non-array shape.
    static func arrayElementType(_ typeText: String) -> String? {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard
            trimmed.hasPrefix("["),
            trimmed.hasSuffix("]"),
            !trimmed.contains(":")
        else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// If `typeText` is a Swift dictionary type (`[K: V]` shorthand or
    /// `Dictionary<K, V>`), returns `(keyType, valueType)` as the inner
    /// Swift type texts. Returns `nil` otherwise.
    static func dictionaryTypes(of typeText: String) -> (keyType: String, valueType: String)? {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            guard let (k, v) = splitTopLevel(inner, on: ":") else { return nil }
            return (
                k.trimmingCharacters(in: .whitespaces),
                v.trimmingCharacters(in: .whitespaces),
            )
        }
        if trimmed.hasPrefix("Dictionary<"), trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst("Dictionary<".count).dropLast())
            guard let (k, v) = splitTopLevel(inner, on: ",") else { return nil }
            return (
                k.trimmingCharacters(in: .whitespaces),
                v.trimmingCharacters(in: .whitespaces),
            )
        }
        return nil
    }

    /// Splits `s` on the first occurrence of `separator` that is at bracket
    /// depth 0 (so nested generic / dictionary types are preserved).
    static func splitTopLevel(_ s: String, on separator: Character) -> (String, String)? {
        var depth = 0
        for index in s.indices {
            let character = s[index]
            switch character {
            case "<", "[": depth += 1
            case ">", "]": depth -= 1
            case separator where depth == 0:
                let lhs = String(s[s.startIndex ..< index])
                let rhs = String(s[s.index(after: index)...])
                return (lhs, rhs)
            default: break
            }
        }
        return nil
    }

    /// Returns the Kotlin rendering of a value of `swiftType`, transforming
    /// nested-type references via `nameTransform`. Primitives map directly;
    /// arrays / dictionaries recurse; user types use the transformed simple
    /// name.
    static func kotlinType(of swiftType: String, nameTransform: NameTransform) -> String {
        if let primitive = primitive(swiftType) {
            return primitive.kotlinType
        }
        if let elem = arrayElementType(swiftType) {
            return "List<\(kotlinType(of: elem, nameTransform: nameTransform))>"
        }
        if let (k, v) = dictionaryTypes(of: swiftType) {
            let keyType = kotlinType(of: k, nameTransform: nameTransform)
            let valueType = kotlinType(of: v, nameTransform: nameTransform)
            return "Map<\(keyType), \(valueType)>"
        }
        return nameTransform.apply(to: simpleName(of: swiftType))
    }
}
