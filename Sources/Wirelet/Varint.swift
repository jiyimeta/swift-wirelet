import Foundation

extension WireFormatWriter {
    /// Append an unsigned little-endian base-128 varint (7 bits per byte,
    /// high bit set on all but the last byte).
    public mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            appendBytes([UInt8(v & 0x7F) | 0x80])
            v >>= 7
        }
        appendBytes([UInt8(v)])
    }

    /// Append a signed value using zig-zag encoding before varint.
    public mutating func writeZigZagVarint(_ value: Int64) {
        let zz = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        writeVarint(zz)
    }
}

extension WireFormatReader {
    /// Read a single byte, advancing the cursor.
    public mutating func readUInt8() throws -> UInt8 {
        try readInteger(UInt8.self)
    }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0 ..< 10 {
            let byte = try readUInt8()
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw WireFormatError.varintOverflow
    }

    public mutating func readZigZagVarint() throws -> Int64 {
        let zz = try readVarint()
        let v = Int64(bitPattern: zz >> 1) ^ -(Int64(bitPattern: zz & 1))
        return v
    }
}
