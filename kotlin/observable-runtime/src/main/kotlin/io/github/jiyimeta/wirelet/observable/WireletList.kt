package io.github.jiyimeta.wirelet.observable

import io.github.jiyimeta.wirelet.BinaryReader
import io.github.jiyimeta.wirelet.BinaryWriter

/**
 * Wire-format helpers for `Array<T: WireFormat>` properties bridged through
 * `@WireletObservable`. Mirrors `WireletObservableJNI.encodeArray` /
 * `decodeArray` on the Swift side.
 *
 * On the wire:
 *
 *     [ varint count ]
 *     [ len₀ + payload₀ ]
 *     [ len₁ + payload₁ ]
 *     …
 *
 * Each element is length-delimited so [decode] / [encode] can stream a
 * heterogeneous count without buffering. The `payload` portion is whatever
 * the codec's `decodePayload(BinaryReader)` consumes / `encodePayload(value,
 * BinaryWriter)` writes — i.e. the same payload a struct codec would emit
 * inside its own outer length-prefixed block.
 *
 * Method-reference call sites:
 *
 *     val items: List<TodoItem> = WireletList.decode(bytes, TodoItemCodec::decodePayload)
 *     val bytes: ByteArray = WireletList.encode(items, TodoItemCodec::encodePayload)
 *
 * Passing function references rather than a `WireletElementCodec` interface
 * means the existing `WireletKotlinEmitter`-produced codec objects do not
 * need a retrofitted supertype.
 */
object WireletList {
    fun <T> decode(bytes: ByteArray, decodePayload: (BinaryReader) -> T): List<T> {
        val r = BinaryReader(bytes)
        val count = r.readVarint().toInt()
        return List(count) { r.readLengthPrefixed { decodePayload(it) } }
    }

    fun <T> encode(value: List<T>, encodePayload: (T, BinaryWriter) -> Unit): ByteArray {
        val w = BinaryWriter()
        w.writeVarint(value.size.toLong())
        for (element in value) {
            w.writeLengthPrefixed { encodePayload(element, this) }
        }
        return w.toByteArray()
    }
}
