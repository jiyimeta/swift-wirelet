import Testing
import Foundation
@testable import Wirelet

@WireFormat
struct WithExplicitTag {
    var a: Int32
    @WireFormatField(tag: 7) var b: Int32
    var c: Int32
}

@WireFormat(reservedTags: [1, 2])
struct WithReservedTags {
    var a: Int32
    var b: Int32
}

@WireFormat(reservedTags: [4])
struct WithMixedReservedAndExplicit {
    @WireFormatField(tag: 9) var first: Int32
    var second: Int32
}

@Test func explicitTagRoundTrip() throws {
    let original = WithExplicitTag(a: 1, b: 2, c: 3)
    let data = original.encodeToData()
    let decoded = try WithExplicitTag(decoding: data)
    #expect(decoded.a == 1)
    #expect(decoded.b == 2)
    #expect(decoded.c == 3)
}

@Test func explicitTagWireBytesUseDeclaredTag() throws {
    // Verify the explicit tag actually lands at tag 7 on the wire.
    let original = WithExplicitTag(a: 10, b: 20, c: 30)
    let data = original.encodeToData()

    var reader = WireFormatReader(data: data)
    let len = Int(try reader.readVarint())
    let slice = try reader.readBytes(count: len)
    var inner = WireFormatReader(data: slice)

    var seenTags: [UInt32] = []
    while !inner.isAtEnd {
        let (tag, wt) = try inner.readTag()
        seenTags.append(tag)
        try inner.skipUnknownField(wireType: wt)
    }
    // Implicit a -> 1, explicit b -> 7, implicit c resumes at 2.
    #expect(seenTags == [1, 7, 2])
}

@Test func reservedTagsSkippedByImplicit() throws {
    // With reservedTags [1, 2], implicit assignment starts at 3.
    let original = WithReservedTags(a: 100, b: 200)
    let data = original.encodeToData()

    var reader = WireFormatReader(data: data)
    let len = Int(try reader.readVarint())
    let slice = try reader.readBytes(count: len)
    var inner = WireFormatReader(data: slice)

    var seenTags: [UInt32] = []
    while !inner.isAtEnd {
        let (tag, wt) = try inner.readTag()
        seenTags.append(tag)
        try inner.skipUnknownField(wireType: wt)
    }
    #expect(seenTags == [3, 4])

    let decoded = try WithReservedTags(decoding: data)
    #expect(decoded.a == 100)
    #expect(decoded.b == 200)
}

@Test func mixedReservedAndExplicitRoundTrip() throws {
    // first explicit @9, second implicit must skip reserved 4 -> lands at 1.
    let original = WithMixedReservedAndExplicit(first: 11, second: 22)
    let data = original.encodeToData()
    let decoded = try WithMixedReservedAndExplicit(decoding: data)
    #expect(decoded.first == 11)
    #expect(decoded.second == 22)
}
