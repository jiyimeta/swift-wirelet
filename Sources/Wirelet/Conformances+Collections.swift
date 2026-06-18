import Foundation

// MARK: - Array — wire type 2 (length-delimited): varint length + concatenated element payloads.

extension Array: WireFormatEncodable where Element: WireFormatEncodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            for element in self {
                // Use `encode(into:)` so nested @WireFormat element types
                // get their own length prefix and remain self-delimiting
                // within the array body. For primitives this is byte-
                // identical to `encodePayload(into:)`.
                element.encode(into: &inner)
            }
        }
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Array: WireFormatDecodable where Element: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        var result: [Element] = []
        try reader.readLengthPrefixed { inner in
            while !inner.isAtEnd {
                try result.append(Element(from: &inner))
            }
        }
        self = result
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - Dictionary — wire type 2 (length-delimited):
// varint(payload length) + varint(entry count) + concatenated (K_payload, V_payload) pairs.
//
// Both keys and values are written as their bare payloads (no inner tags).
// To make the encoding byte-identical across languages independent of
// Dictionary's intrinsic unordered iteration, entries are canonicalized by
// sorting on the encoded-key bytes (lexicographic). The encode constraint is
// `Key: WireFormatEncodable` rather than `Comparable` — we sort the encoded
// bytes, not the key's intrinsic order.

extension Dictionary: WireFormatEncodable
where Key: WireFormatEncodable, Value: WireFormatEncodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        // Encode each key's payload to bytes once; sort entries by encoded-key
        // bytes for canonical cross-language order.
        // Use `encode(into:)` (not `encodePayload`) for both K and V so
        // nested @WireFormat types get their own length prefix and remain
        // self-delimiting within the entry stream. For primitives this is
        // byte-identical to `encodePayload(into:)`.
        let encodedKeys: [(keyBytes: Data, value: Value)] = map { entry in
            var keyWriter = WireFormatWriter()
            entry.key.encode(into: &keyWriter)
            return (keyWriter.data, entry.value)
        }
        let sorted = encodedKeys.sorted { lhs, rhs in
            lhs.keyBytes.lexicographicallyPrecedes(rhs.keyBytes)
        }
        writer.writeLengthPrefixed { inner in
            inner.writeVarint(UInt64(sorted.count))
            for entry in sorted {
                inner.appendBytes(entry.keyBytes)
                entry.value.encode(into: &inner)
            }
        }
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Dictionary: WireFormatDecodable
where Key: WireFormatDecodable & Hashable, Value: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        var dict: [Key: Value] = [:]
        try reader.readLengthPrefixed { inner in
            let count = try Int(inner.readVarint())
            dict.reserveCapacity(count)
            for _ in 0 ..< count {
                let k = try Key(from: &inner)
                let v = try Value(from: &inner)
                dict[k] = v
            }
        }
        self = dict
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}
