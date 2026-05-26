package io.github.jiyimeta.wirelet

/**
 * Errors thrown by the TLV decoder.
 *
 * Mirrors the Swift `WireFormatError` cases so that cross-language
 * conformance tests can assert on equivalent failure modes.
 */
sealed class WireFormatException(message: String) : RuntimeException(message) {
    class Truncated(needed: Int, remaining: Int) :
        WireFormatException("needed $needed, remaining $remaining")
    class InvalidCount(count: Int) :
        WireFormatException("invalid count $count")
    class InvalidUtf8 :
        WireFormatException("invalid UTF-8 in string payload")
    class UnknownWireType(code: Int) :
        WireFormatException("unknown wire type code $code")
    class VarintOverflow :
        WireFormatException("varint exceeded 10 bytes")
    class UnknownTag(tag: Int, wireType: WireType) :
        WireFormatException("unknown tag $tag (wire type $wireType)")
    class UnknownChoiceDiscriminator(disc: Int) :
        WireFormatException("unknown choice discriminator $disc")
}
