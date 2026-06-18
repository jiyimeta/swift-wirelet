package io.github.jiyimeta.wirelet

/**
 * Lexicographic (unsigned) comparator over `ByteArray`. Used by generated
 * `Map` codecs to canonical-sort entries by their encoded key bytes so
 * the wire format is byte-identical to the Swift side (Conformances.swift
 * uses `Data.lexicographicallyPrecedes`).
 *
 * Bytes are compared as unsigned values to match Swift's `Data`
 * comparison and the natural sort over byte sequences.
 */
public object ByteArrayLexComparator : Comparator<ByteArray> {
    override fun compare(
        a: ByteArray,
        b: ByteArray,
    ): Int {
        val n = minOf(a.size, b.size)
        for (i in 0 until n) {
            val ai = a[i].toInt() and 0xFF
            val bi = b[i].toInt() and 0xFF
            if (ai != bi) return ai - bi
        }
        return a.size - b.size
    }
}
