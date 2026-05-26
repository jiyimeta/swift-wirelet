import Foundation

// MARK: - Unsigned fixed-width integers — varint wire type.

extension UInt8: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(UInt64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension UInt8: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readVarint()
        self = UInt8(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension UInt16: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(UInt64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension UInt16: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readVarint()
        self = UInt16(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension UInt32: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(UInt64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension UInt32: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readVarint()
        self = UInt32(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension UInt64: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeVarint(self)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension UInt64: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        self = try reader.readVarint()
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - Signed fixed-width integers — zig-zag varint wire type.

extension Int8: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeZigZagVarint(Int64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Int8: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readZigZagVarint()
        self = Int8(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension Int16: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeZigZagVarint(Int64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Int16: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readZigZagVarint()
        self = Int16(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension Int32: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeZigZagVarint(Int64(self))
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Int32: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        let v = try reader.readZigZagVarint()
        self = Int32(truncatingIfNeeded: v)
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

extension Int64: WireFormatEncodable {
    public static var wireType: WireType { .varint }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeZigZagVarint(self)
    }

    public func encode(into writer: inout WireFormatWriter) {
        encodePayload(into: &writer)
    }
}

extension Int64: WireFormatDecodable {
    public init(decodingPayload reader: inout WireFormatReader) throws {
        self = try reader.readZigZagVarint()
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}

// MARK: - Bool — varint (0 / 1).

extension Bool: WireFormatEncodable {
    public static var wireType: WireType { .varint }

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
    public static var wireType: WireType { .fixed32 }

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
    public static var wireType: WireType { .fixed64 }

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
    public static var wireType: WireType { .lengthDelimited }

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
        let count = Int(try reader.readVarint())
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

// MARK: - Array — wire type 2 (length-delimited): varint length + concatenated element payloads.

extension Array: WireFormatEncodable where Element: WireFormatEncodable {
    public static var wireType: WireType { .lengthDelimited }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            for element in self {
                element.encodePayload(into: &inner)
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
                try result.append(Element(decodingPayload: &inner))
            }
        }
        self = result
    }

    public init(from reader: inout WireFormatReader) throws {
        try self.init(decodingPayload: &reader)
    }
}
