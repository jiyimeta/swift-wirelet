import Foundation

/// Minimal little-endian byte sink for wire-format encoding.
public struct WireFormatWriter {
    public private(set) var data = Data()

    public init() {}

    /// Append a fixed-width integer in little-endian byte order.
    public mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    /// Append raw bytes (no endianness reinterpretation).
    public mutating func appendBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        data.append(contentsOf: bytes)
    }
}

extension WireFormatWriter {
    /// Encode a `(tag, wireType)` pair as a single varint.
    public mutating func writeTag(tag: UInt32, wireType: WireType) {
        writeVarint(UInt64(tag) << 3 | UInt64(wireType.rawValue))
    }

    /// Buffers the body, then writes its varint length, then the bytes.
    /// Body callback receives an inner writer to avoid double-writes.
    public mutating func writeLengthPrefixed(_ body: (inout WireFormatWriter) -> Void) {
        var inner = WireFormatWriter()
        body(&inner)
        writeVarint(UInt64(inner.data.count))
        appendBytes(inner.data)
    }
}
