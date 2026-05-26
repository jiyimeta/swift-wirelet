package io.github.jiyimeta.wirelet

/**
 * Wire-format type tag stored in the low 3 bits of every TLV record header.
 *
 * Mirrors the Swift `WireType` enum in the wirelet runtime so that bytes
 * produced by one side decode cleanly on the other.
 */
enum class WireType(val code: Int) {
    VARINT(0),
    FIXED64(1),
    LENGTH_DELIMITED(2),
    FIXED32(5);

    companion object {
        fun fromCode(code: Int): WireType =
            entries.firstOrNull { it.code == code }
                ?: throw WireFormatException.UnknownWireType(code)
    }
}
