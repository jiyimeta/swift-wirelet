package io.github.jiyimeta.wirelet.observable

import io.github.jiyimeta.wirelet.BinaryReader
import io.github.jiyimeta.wirelet.BinaryWriter
import kotlin.test.Test
import kotlin.test.assertEquals

class WireletListTest {

    /** Toy WireFormat-style element used by the round-trip tests. */
    private data class Pair2(val a: Int, val b: Int)

    private fun encodePair(value: Pair2, w: BinaryWriter) {
        w.writeTag(1, io.github.jiyimeta.wirelet.WireType.VARINT)
        w.writeZigZagVarint(value.a.toLong())
        w.writeTag(2, io.github.jiyimeta.wirelet.WireType.VARINT)
        w.writeZigZagVarint(value.b.toLong())
    }

    private fun decodePair(r: BinaryReader): Pair2 {
        var a: Int? = null
        var b: Int? = null
        while (r.remaining > 0) {
            val (tag, wt) = r.readTag()
            when (tag) {
                1 -> a = r.readZigZagVarint().toInt()
                2 -> b = r.readZigZagVarint().toInt()
                else -> r.skipUnknownField(wt)
            }
        }
        return Pair2(a ?: error("missing field 1"), b ?: error("missing field 2"))
    }

    @Test
    fun roundTripPreservesOrder() {
        val original = listOf(Pair2(1, -2), Pair2(3, 4), Pair2(-5, 6))
        val bytes = WireletList.encode(original, ::encodePair)
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(original, decoded)
    }

    @Test
    fun roundTripEmptyList() {
        val bytes = WireletList.encode(emptyList<Pair2>(), ::encodePair)
        // Empty payload after varint(0): single zero byte.
        assertEquals(1, bytes.size)
        assertEquals(0.toByte(), bytes[0])
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(emptyList(), decoded)
    }

    @Test
    fun thousandElementRoundTrip() {
        val original = (0 until 1_000).map { Pair2(it, it * 2) }
        val bytes = WireletList.encode(original, ::encodePair)
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(original, decoded)
        assertEquals(1_000, decoded.size)
    }

    @Test
    fun decodeIsTolerantOfUnknownTrailingTagsInPayload() {
        // Manually craft a payload whose Pair2 record has an extra tag-3 field
        // that decodePair must skip.
        val outer = BinaryWriter()
        outer.writeVarint(1L)
        outer.writeLengthPrefixed {
            writeTag(1, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(7L)
            writeTag(2, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(8L)
            // Unknown extra field — must be skipped, not error.
            writeTag(99, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(0L)
        }
        val decoded = WireletList.decode(outer.toByteArray(), ::decodePair)
        assertEquals(listOf(Pair2(7, 8)), decoded)
    }
}
