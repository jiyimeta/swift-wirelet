import Foundation
import Testing
@testable import Wirelet

@WireFormat
struct WithOptional {
    var a: Int32
    var b: Int32?
}

@WireFormat
struct OptionalV1 {
    var a: Int32
}

@WireFormat
struct OptionalV2 {
    var a: Int32
    var b: Int32?
}

@WireFormat
struct WithExplicitOptional {
    var a: Int32
    var b: Int32?
}

@Test func optionalAbsentDecodeAsNil() throws {
    let v = WithOptional(a: 5, b: nil)
    let data = v.encodeToData()
    let decoded = try WithOptional(decoding: data)
    #expect(decoded.a == 5)
    #expect(decoded.b == nil)
}

@Test func optionalPresentRoundTrip() throws {
    let v = WithOptional(a: 5, b: 42)
    let decoded = try WithOptional(decoding: v.encodeToData())
    #expect(decoded.a == 5)
    #expect(decoded.b == 42)
}

@Test func optionalAbsentNoTagOnWire() {
    let v = WithOptional(a: 5, b: nil)
    let data = v.encodeToData()
    // Inner body should contain only tag 1 (varint) + zig-zag(5).
    // tag(1, varint=0) = 0x08. zig-zag(5) = varint(10) = 0x0A.
    // encode() wraps in writeLengthPrefixed: [varint(2)=0x02, 0x08, 0x0A].
    #expect(data == Data([0x02, 0x08, 0x0A]))
}

@Test func forwardCompatTtoOptionalT() throws {
    // Encode using a v1 struct with only field a, decode with v2 (a + optional b).
    let v1 = OptionalV1(a: 5)
    let v1Data = v1.encodeToData()
    let v2 = try OptionalV2(decoding: v1Data)
    #expect(v2.a == 5)
    #expect(v2.b == nil)
}

@Test func explicitOptionalSyntaxRoundTrip() throws {
    // Verify `Optional<T>` (non-sugar) form is detected and behaves identically.
    let absent = WithExplicitOptional(a: 1, b: nil)
    let absentDecoded = try WithExplicitOptional(decoding: absent.encodeToData())
    #expect(absentDecoded.a == 1)
    #expect(absentDecoded.b == nil)

    let present = WithExplicitOptional(a: 1, b: 7)
    let presentDecoded = try WithExplicitOptional(decoding: present.encodeToData())
    #expect(presentDecoded.a == 1)
    #expect(presentDecoded.b == 7)
}
