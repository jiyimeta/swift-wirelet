import Foundation

// MARK: - Unsigned fixed-width integers — varint wire type.

extension UInt8: WireFormatEncodable {
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
    public static var wireType: WireType {
        .varint
    }

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
