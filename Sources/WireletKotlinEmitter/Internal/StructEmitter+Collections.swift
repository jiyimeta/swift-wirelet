import WireletSchema

/// Array / Dictionary payload emit helpers for `StructEmitter`. Split out of
/// `StructEmitter.swift` to keep that file under the file-length limit; these
/// are the recursive collection-type emitters that `payloadWrite` /
/// `decodeExpr` dispatch into.
extension StructEmitter {
    // MARK: - Array helpers

    static func arrayWrite(
        elemType: String,
        valueExpr: String,
        writerName: String,
        transform: NameTransform,
    ) -> [String] {
        var lines: [String] = []
        lines.append("\(writerName).writeLengthPrefixed {")
        let inner = payloadWrite(typeText: elemType, valueExpr: "e", writerName: "this", transform: transform)
        if inner.count == 1 {
            lines.append("    for (e in \(valueExpr)) \(inner[0])")
        } else {
            lines.append("    for (e in \(valueExpr)) {")
            for ln in inner {
                lines.append("        \(ln)")
            }
            lines.append("    }")
        }
        lines.append("}")
        return lines
    }

    static func arrayReadExpr(
        elemType: String,
        readerName: String,
        transform: NameTransform,
    ) -> String {
        let kotlinElem = KotlinTypeMap.kotlinType(of: elemType, nameTransform: transform)
        let readOne = decodeExpr(typeText: elemType, readerName: "it", transform: transform)
        let body = "val list = ArrayList<\(kotlinElem)>(); "
            + "while (it.remaining > 0) list.add(\(readOne)); list"
        return "\(readerName).readLengthPrefixed { \(body) }"
    }

    // MARK: - Dictionary helpers

    /// Emits a *canonical* dictionary encode: each entry's key is first
    /// written to a scratch `BinaryWriter`, entries are sorted by their
    /// encoded-key bytes (lexicographic, unsigned-byte comparison via
    /// `ByteArrayLexComparator`), then count + sorted (keyBytes, value)
    /// pairs are emitted. Matches Swift's `Dictionary.encodePayload`
    /// canonicalisation so multi-entry Maps round-trip byte-identically
    /// between Swift and Kotlin. Decode is symmetric (order doesn't
    /// matter when populating the target `MutableMap`).
    static func dictionaryWrite(
        keyType: String,
        valueType: String,
        valueExpr: String,
        writerName: String,
        transform: NameTransform,
    ) -> [String] {
        let writeKInto = payloadWrite(
            typeText: keyType,
            valueExpr: "entry.key",
            writerName: "kw",
            transform: transform,
        )
        // Use `entryValue` as the destructured local so we don't shadow
        // the codec's outer `value` parameter (Kotlin emits a warning).
        let writeV = payloadWrite(
            typeText: valueType,
            valueExpr: "entryValue",
            writerName: "this",
            transform: transform,
        )
        var lines: [String] = []
        lines.append("\(writerName).writeLengthPrefixed {")
        lines.append("    val sortedEntries = (\(valueExpr)).entries.map { entry ->")
        lines.append("        val kw = BinaryWriter()")
        for ln in writeKInto {
            lines.append("        \(ln)")
        }
        lines.append("        kw.toByteArray() to entry.value")
        lines.append("    }.sortedWith(compareBy(ByteArrayLexComparator) { it.first })")
        lines.append("    writeVarint(sortedEntries.size.toLong())")
        lines.append("    for ((keyBytes, entryValue) in sortedEntries) {")
        lines.append("        writeBytes(keyBytes)")
        for ln in writeV {
            lines.append("        \(ln)")
        }
        lines.append("    }")
        lines.append("}")
        return lines
    }

    static func dictionaryReadExpr(
        keyType: String,
        valueType: String,
        readerName: String,
        transform: NameTransform,
    ) -> String {
        let kk = KotlinTypeMap.kotlinType(of: keyType, nameTransform: transform)
        let vv = KotlinTypeMap.kotlinType(of: valueType, nameTransform: transform)
        // Rename the outer lambda parameter to `dr` (dictionary reader) so
        // that `repeat(count) { ... }`'s implicit `it: Int` doesn't shadow
        // the reader inside the loop body.
        let readK = decodeExpr(typeText: keyType, readerName: "dr", transform: transform)
        let readV = decodeExpr(typeText: valueType, readerName: "dr", transform: transform)
        let prelude = "val count = dr.readVarint().toInt(); "
            + "val m = LinkedHashMap<\(kk), \(vv)>(count); "
        let loop = "repeat(count) { val k = \(readK); val v = \(readV); m[k] = v }; m"
        let body = "dr -> \(prelude)\(loop)"
        return "\(readerName).readLengthPrefixed { \(body) }"
    }
}
