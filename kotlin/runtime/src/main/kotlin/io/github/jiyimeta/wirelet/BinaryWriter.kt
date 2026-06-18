package io.github.jiyimeta.wirelet

/**
 * Sequential little-endian binary writer. Used by every code-generated
 * codec produced by `emit-wirelet-kotlin`.
 *
 * Mirrors the write side of the Swift wire-format encoder.
 */
class BinaryWriter {
    private val out = mutableListOf<Byte>()

    fun writeU8(v: Int) {
        out += (v and 0xFF).toByte()
    }

    fun writeU8(v: UByte) {
        out += v.toByte()
    }

    fun writeU8(v: UInt) {
        out += (v and 0xFFu).toByte()
    }

    fun writeU16(v: Int) {
        writeU8(v and 0xFF)
        writeU8((v shr 8) and 0xFF)
    }

    fun writeI32(v: Int) {
        for (i in 0..3) writeU8((v shr (i * 8)) and 0xFF)
    }

    fun writeI64(v: Long) {
        for (i in 0..7) writeU8(((v shr (i * 8)) and 0xFF).toInt())
    }

    fun writeU32(v: Long) {
        for (i in 0..3) writeU8(((v shr (i * 8)) and 0xFF).toInt())
    }

    fun writeF32(v: Float) {
        writeI32(java.lang.Float.floatToRawIntBits(v))
    }

    fun writeF64(v: Double) {
        writeI64(v.toRawBits())
    }

    fun writeString(v: String) {
        val bytes = v.toByteArray(Charsets.UTF_8)
        writeI32(bytes.size)
        for (b in bytes) writeU8(b.toInt() and 0xFF)
    }

    /** Append raw bytes without any length prefix. */
    fun writeBytes(bytes: ByteArray) {
        for (b in bytes) out += b
    }

    // --- TLV primitives (mirror of Swift Wirelet runtime) ---

    /** Unsigned little-endian base-128 varint, max 10 bytes for a 64-bit value. */
    fun writeVarint(value: Long) {
        var v = value
        while (v.toULong() >= 0x80UL) {
            writeU8(((v and 0x7F) or 0x80).toInt())
            v = v ushr 7
        }
        writeU8((v and 0xFF).toInt())
    }

    /** ZigZag-encoded signed varint (small magnitudes encode short regardless of sign). */
    fun writeZigZagVarint(value: Long) {
        val zz = (value shl 1) xor (value shr 63)
        writeVarint(zz)
    }

    /** Field header: (tag << 3) | wireType, written as a varint. */
    fun writeTag(
        tag: Int,
        wireType: WireType,
    ) {
        writeVarint((tag.toLong() shl 3) or wireType.code.toLong())
    }

    /**
     * Write a length-delimited payload: the [body] writes into a scratch
     * writer; its bytes are then emitted with a varint length prefix.
     */
    fun writeLengthPrefixed(body: BinaryWriter.() -> Unit) {
        val inner = BinaryWriter()
        inner.body()
        val payload = inner.toByteArray()
        writeVarint(payload.size.toLong())
        writeBytes(payload)
    }

    fun toByteArray(): ByteArray = out.toByteArray()
}
