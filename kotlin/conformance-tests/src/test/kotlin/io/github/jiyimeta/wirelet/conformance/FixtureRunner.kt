// Kotlin-side cross-language conformance suite (Task 2.14).
//
// Mirrors Tests/ConformanceTests/FixtureRunner.swift: decode each
// committed .bin fixture, assert canonical field values, then re-encode
// and assert byte-identical to the original — proving the Kotlin codec
// is a faithful peer of the Swift macro-generated codec.

package io.github.jiyimeta.wirelet.conformance

import io.github.jiyimeta.wirelet.conformance.model.OptionalHolder
import io.github.jiyimeta.wirelet.conformance.model.Primitives
import io.github.jiyimeta.wirelet.conformance.model.ShapeChoice
import io.github.jiyimeta.wirelet.conformance.serialization.OptionalHolderCodec
import io.github.jiyimeta.wirelet.conformance.serialization.PrimitivesCodec
import io.github.jiyimeta.wirelet.conformance.serialization.ShapeChoiceCodec
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FixtureRunner {
    private fun fixture(name: String): ByteArray =
        File("fixtures/$name").readBytes()

    @Test fun primitives() {
        val bytes = fixture("primitives_v1.bin")
        val v = PrimitivesCodec.decode(bytes)
        assertEquals(7u, v.u32)
        assertEquals(-3, v.i32)
        assertEquals(1.5f, v.f)
        assertEquals(2.25, v.d)
        assertEquals("hi", v.s)
        assertEquals(true, v.b)
        val reencoded = PrimitivesCodec.encode(v)
        assertContentEquals(bytes, reencoded)
    }

    @Test fun optionalPresent() {
        val bytes = fixture("optional_present_v1.bin")
        val v = OptionalHolderCodec.decode(bytes)
        assertEquals(5, v.a)
        assertEquals(42, v.b)
        assertContentEquals(bytes, OptionalHolderCodec.encode(v))
    }

    @Test fun optionalAbsent() {
        val bytes = fixture("optional_absent_v1.bin")
        val v = OptionalHolderCodec.decode(bytes)
        assertEquals(5, v.a)
        assertNull(v.b)
        assertContentEquals(bytes, OptionalHolderCodec.encode(v))
    }

    @Test fun choice() {
        val bytes = fixture("choice_v1.bin")
        val v = ShapeChoiceCodec.decode(bytes)
        require(v is ShapeChoice.Point) { "expected Point, got $v" }
        assertEquals(3, v.arg0)
        assertEquals(-7, v.arg1)
        assertContentEquals(bytes, ShapeChoiceCodec.encode(v))
    }

    @Test fun forwardCompatV2ToV1() {
        // Bytes were produced by Swift's OptionalHolderV2 (a, b, c).
        // Decoding with v1 schema must skip tag 3 (`c`) and recover (a, b).
        // No byte-equal re-encode check: v1 lacks tag 3 by definition.
        val bytes = fixture("forward_compat_v2_to_v1.bin")
        val v = OptionalHolderCodec.decode(bytes)
        assertEquals(5, v.a)
        assertEquals(42, v.b)
    }
}
