package io.github.jiyimeta.wirelet

/**
 * Sequential little-endian binary reader. Used by every code-generated
 * codec produced by `emit-wirelet-kotlin`.
 *
 * Mirrors the read side of the Swift wire-format encoder. Multi-byte
 * integers are little-endian (matching Swift's `withUnsafeBytes` store
 * order on the wire).
 */
class BinaryReader(private val data: ByteArray) {
    private var offset = 0

    val remaining: Int get() = data.size - offset

    class UnderflowException : Exception("BinaryReader underflow")

    fun readU8(): UByte {
        if (offset >= data.size) throw UnderflowException()
        return data[offset++].toUByte()
    }

    fun readU16(): Int {
        val lo = readU8().toInt()
        val hi = readU8().toInt()
        return lo or (hi shl 8)
    }

    fun readI32(): Int {
        var v = 0
        for (i in 0..3) v = v or (readU8().toInt() shl (i * 8))
        return v
    }

    fun readI64(): Long {
        var v = 0L
        for (i in 0..7) v = v or (readU8().toLong() shl (i * 8))
        return v
    }

    fun readU32(): Long {
        var v = 0L
        for (i in 0..3) v = v or (readU8().toLong() shl (i * 8))
        return v
    }

    fun readF32(): Float = java.lang.Float.intBitsToFloat(readI32())

    fun readF64(): Double = Double.fromBits(readI64())

    fun readString(): String {
        val len = readI32()
        if (len < 0 || len > remaining) throw UnderflowException()
        val bytes = ByteArray(len)
        for (i in 0 until len) bytes[i] = readU8().toByte()
        return String(bytes, Charsets.UTF_8)
    }

    /** Read [count] raw bytes. Throws [WireFormatException.Truncated] if short. */
    fun readBytes(count: Int): ByteArray {
        if (count < 0) throw WireFormatException.InvalidCount(count)
        if (count > remaining) throw WireFormatException.Truncated(count, remaining)
        val bytes = ByteArray(count)
        for (i in 0 until count) bytes[i] = readU8().toByte()
        return bytes
    }

    // --- TLV primitives (mirror of Swift Wirelet runtime) ---

    /** Decode an unsigned little-endian base-128 varint (up to 10 bytes). */
    fun readVarint(): Long {
        var result = 0L
        var shift = 0
        repeat(10) {
            val byte = readU8().toInt()
            result = result or ((byte.toLong() and 0x7FL) shl shift)
            if (byte and 0x80 == 0) return result
            shift += 7
        }
        throw WireFormatException.VarintOverflow()
    }

    /** Decode a ZigZag-encoded signed varint. */
    fun readZigZagVarint(): Long {
        val zz = readVarint()
        return (zz ushr 1) xor -(zz and 1L)
    }

    /** Decode a field header into (tag, wireType). */
    fun readTag(): Pair<Int, WireType> {
        val raw = readVarint()
        val wt = WireType.fromCode((raw and 0b111L).toInt())
        val tag = (raw ushr 3).toInt()
        return tag to wt
    }

    /**
     * Read a length-prefixed payload, slice it, and hand a dedicated
     * [BinaryReader] over that slice to [body]. The outer cursor is
     * advanced past the slice regardless of how much [body] consumes.
     */
    fun <R> readLengthPrefixed(body: (BinaryReader) -> R): R {
        val len = readVarint().toInt()
        val slice = readBytes(len)
        return body(BinaryReader(slice))
    }

    /** Skip a TLV field of the given wire type without interpreting it. */
    fun skipUnknownField(wireType: WireType) {
        when (wireType) {
            WireType.VARINT -> readVarint()
            WireType.FIXED64 -> readBytes(8)
            WireType.LENGTH_DELIMITED -> readLengthPrefixed { /* discard */ }
            WireType.FIXED32 -> readBytes(4)
        }
    }
}
