package io.github.jiyimeta.wirelet

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class VarintTest {
    @Test fun unsignedRoundTrip() {
        listOf(0L, 1L, 127L, 128L, 16383L, 16384L, Long.MAX_VALUE).forEach { v ->
            val w = BinaryWriter().apply { writeVarint(v) }
            val r = BinaryReader(w.toByteArray())
            assertEquals(v, r.readVarint())
        }
    }

    @Test fun zigZagRoundTrip() {
        listOf(0L, -1L, 1L, -2L, 2L, Long.MIN_VALUE, Long.MAX_VALUE).forEach { v ->
            val w = BinaryWriter().apply { writeZigZagVarint(v) }
            val r = BinaryReader(w.toByteArray())
            assertEquals(v, r.readZigZagVarint())
        }
    }

    @Test fun varintOverflow() {
        val bytes = ByteArray(11) { 0x80.toByte() }
        assertFailsWith<WireFormatException.VarintOverflow> {
            BinaryReader(bytes).readVarint()
        }
    }
}
