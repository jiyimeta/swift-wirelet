import Foundation

// MARK: - Bool — varint (0 / 1).

extension Bool: WireFormatEncodable {
    public static var wireType: WireType {
        .varint
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(self ? 1 : 0)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Bool: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readVarint()
        self = v != 0
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - Float / Double — IEEE 754 little-endian via bitPattern.

extension Float: WireFormatEncodable {
    public static var wireType: WireType {
        .fixed32
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.appendInteger(bitPattern)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Float: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let bits = try reader.readInteger(UInt32.self)
        self = Float(bitPattern: bits)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension Double: WireFormatEncodable {
    public static var wireType: WireType {
        .fixed64
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.appendInteger(bitPattern)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Double: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let bits = try reader.readInteger(UInt64.self)
        self = Double(bitPattern: bits)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - String — varint length + UTF-8 bytes.

extension String: WireFormatEncodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        let bytes = Array(utf8)
        writer.writeVarint(UInt64(bytes.count))
        writer.appendBytes(bytes)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension String: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let count = try Int(reader.readVarint())
        let bytes = try reader.readBytes(count: count)
        guard let s = String(data: bytes, encoding: .utf8) else {
            throw WireFormatError.invalidUTF8
        }
        self = s
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - Data — wire type 2 (length-delimited): varint length + raw bytes.
//
// We do not add a separate `[UInt8]` conformance because Swift does not
// support overlapping conditional conformances — the generic
// `Array: WireFormatEncodable where Element: WireFormatEncodable`
// conformance below already covers `[UInt8]`, but with per-element
// varint encoding (not raw bytes). Callers who want a length-prefixed
// raw byte field should use `Data`, which has the dedicated encoding.

extension Data: WireFormatEncodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(UInt64(count))
        writer.appendBytes(self)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Data: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let count = try Int(reader.readVarint())
        self = try reader.readBytes(count: count)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}
