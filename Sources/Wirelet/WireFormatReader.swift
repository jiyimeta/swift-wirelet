import Foundation

/// Forward-only little-endian byte cursor for wire-format decoding.
///
/// The reader is value-type — `try Foo(from: &reader)` advances the
/// cursor in-place. Pass `inout` consistently to keep that semantic.
public struct WireFormatReader {
    public let data: Data
    public private(set) var offset = 0

    public init(data: Data) {
        self.data = data
    }

    public var remaining: Int {
        data.count - offset
    }

    public var isAtEnd: Bool {
        offset >= data.count
    }

    /// Read a fixed-width integer in little-endian byte order.
    public mutating func readInteger<T: FixedWidthInteger>(_: T.Type = T.self) throws -> T {
        let size = MemoryLayout<T>.size
        guard remaining >= size else {
            throw WireFormatError.truncated(needed: size, remaining: remaining)
        }
        let value: T = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset += size
        return T(littleEndian: value)
    }

    /// Read `count` raw bytes and advance the cursor.
    public mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw WireFormatError.invalidCount(Int32(clamping: count))
        }
        guard remaining >= count else {
            throw WireFormatError.truncated(needed: count, remaining: remaining)
        }
        let start = data.startIndex + offset
        let slice = data[start ..< (start + count)]
        offset += count
        return Data(slice)
    }
}

extension WireFormatReader {
    /// Read a `(tag, wireType)` pair encoded as a single varint.
    public mutating func readTag() throws -> (tag: UInt32, wireType: WireType) {
        let raw = try readVarint()
        let wtCode = UInt8(raw & 0b111)
        guard let wireType = WireType(rawValue: wtCode) else {
            throw WireFormatError.unknownWireType(wtCode)
        }
        let tag = UInt32(raw >> 3)
        return (tag, wireType)
    }

    /// Read the body length, slice that many bytes into a sub-reader, advance.
    public mutating func readLengthPrefixed<R>(
        _ body: (inout WireFormatReader) throws -> R
    ) throws -> R {
        let len = Int(try readVarint())
        let slice = try readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        return try body(&inner)
    }

    /// Skip a field of the given `wireType`, advancing past its payload.
    public mutating func skipUnknownField(wireType: WireType) throws {
        switch wireType {
        case .varint:           _ = try readVarint()
        case .fixed64:          _ = try readBytes(count: 8)
        case .lengthDelimited:  _ = try readLengthPrefixed { _ in () }
        case .fixed32:          _ = try readBytes(count: 4)
        }
    }
}
