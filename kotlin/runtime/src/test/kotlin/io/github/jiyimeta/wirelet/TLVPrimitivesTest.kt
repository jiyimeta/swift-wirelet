package io.github.jiyimeta.wirelet

import kotlin.test.Test
import kotlin.test.assertEquals

class TLVPrimitivesTest {
    @Test fun tagEncodesWireTypeInLowBits() {
        val w = BinaryWriter().apply { writeTag(7, WireType.LENGTH_DELIMITED) }
        val r = BinaryReader(w.toByteArray())
        val (tag, wt) = r.readTag()
        assertEquals(7, tag)
        assertEquals(WireType.LENGTH_DELIMITED, wt)
    }

    @Test fun lengthPrefixedRoundTrip() {
        val w = BinaryWriter()
        w.writeLengthPrefixed {
            writeVarint(42L)
            writeVarint(43L)
        }
        val r = BinaryReader(w.toByteArray())
        r.readLengthPrefixed { inner ->
            assertEquals(42L, inner.readVarint())
            assertEquals(43L, inner.readVarint())
        }
    }

    @Test fun skipUnknownLengthDelimited() {
        val w = BinaryWriter()
        w.writeTag(99, WireType.LENGTH_DELIMITED)
        w.writeLengthPrefixed { writeBytes(byteArrayOf(0xCA.toByte(), 0xFE.toByte())) }
        w.writeTag(1, WireType.VARINT)
        w.writeVarint(7L)

        val r = BinaryReader(w.toByteArray())
        val (tag1, wt1) = r.readTag()
        assertEquals(99, tag1)
        assertEquals(WireType.LENGTH_DELIMITED, wt1)
        r.skipUnknownField(wt1)
        val (tag2, _) = r.readTag()
        assertEquals(1, tag2)
        assertEquals(7L, r.readVarint())
    }
}
