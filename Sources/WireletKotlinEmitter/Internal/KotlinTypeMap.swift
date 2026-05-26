enum KotlinTypeMap {
    /// Returns `(kotlinType, readerCall, writerCall(_:))` for a Swift
    /// primitive type. Calls use `r`/`w` as the cursor variable names.
    static func primitive(_ swiftType: String) -> (kotlinType: String, read: String, write: (String) -> String)? {
        switch swiftType {
        case "UInt8": return ("UByte", "r.readU8()", { "w.writeU8(\($0))" })
        case "Int8": return ("Byte", "r.readI8()", { "w.writeI8(\($0))" })
        case "UInt16": return ("UShort", "r.readU16()", { "w.writeU16(\($0))" })
        case "Int16": return ("Short", "r.readI16()", { "w.writeI16(\($0))" })
        case "UInt32": return ("UInt", "r.readU32()", { "w.writeU32(\($0))" })
        case "Int32": return ("Int", "r.readI32()", { "w.writeI32(\($0))" })
        case "UInt64": return ("ULong", "r.readU64()", { "w.writeU64(\($0))" })
        case "Int64": return ("Long", "r.readI64()", { "w.writeI64(\($0))" })
        case "Float": return ("Float", "r.readF32()", { "w.writeF32(\($0))" })
        case "Double": return ("Double", "r.readF64()", { "w.writeF64(\($0))" })
        case "Bool": return ("Boolean", "r.readU8() != 0u.toUByte()", { "w.writeU8(if (\($0)) 1u else 0u)" })
        // NOTE: BinaryReader/BinaryWriter in the existing Kotlin codebase do not yet
        // have readString()/writeString() methods (as of 2026-05-23). No current
        // @WireFormat type uses a raw String field, so this does not block codegen.
        // Task 17 will add readString/writeString and verify end-to-end.
        case "String": return ("String", "r.readString()", { "w.writeString(\($0))" })
        // `Data` maps to a length-prefixed `ByteArray` on the Kotlin side.
        // BinaryReader/BinaryWriter readBytes/writeBytes helpers handle
        // the varint length + raw byte payload; see Task 2.10 goldens.
        case "Data": return ("ByteArray", "r.readBytes()", { "w.writeBytes(\($0))" })
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

    /// If `typeText` is a Swift dictionary type (`[K: V]` shorthand or
    /// `Dictionary<K, V>`), returns `(keyType, valueType)` as the inner
    /// Swift type texts. Returns `nil` otherwise.
    ///
    /// Used by the struct emitter (Task 2.10) to map dictionary fields to
    /// Kotlin `Map<K_Kotlin, V_Kotlin>`. This method only parses the type
    /// surface; the caller is responsible for resolving the inner types
    /// (e.g. via `primitive(_:)` or by treating them as referenced codecs).
    static func dictionaryTypes(of typeText: String) -> (keyType: String, valueType: String)? {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        // [K: V] shorthand
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            guard let (k, v) = splitTopLevel(inner, on: ":") else { return nil }
            return (
                k.trimmingCharacters(in: .whitespaces),
                v.trimmingCharacters(in: .whitespaces),
            )
        }
        // Dictionary<K, V> longhand
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
    private static func splitTopLevel(_ s: String, on separator: Character) -> (String, String)? {
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

    /// Returns the Kotlin rendering of a Swift dictionary field type.
    /// `[K: V]` → `Map<K_Kotlin, V_Kotlin>`. Both inner types must resolve
    /// to either a primitive (via `primitive(_:)`) or a referenced model
    /// class — the caller supplies the resolver via `kotlinName(of:)`.
    ///
    /// This is purely the *type* mapping. The encode / decode emit logic
    /// is wired up in Task 2.10.
    static func dictionaryKotlinType(
        of typeText: String,
        kotlinName: (String) -> String,
    ) -> String? {
        guard let (k, v) = dictionaryTypes(of: typeText) else { return nil }
        return "Map<\(kotlinName(k)), \(kotlinName(v))>"
    }
}
