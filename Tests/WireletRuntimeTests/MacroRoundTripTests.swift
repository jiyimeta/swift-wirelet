import Testing
import Foundation
@testable import Wirelet

@WireFormat
struct MacroRoundTripPoint {
    var x: Int32
    var y: Int32
}

@WireFormat
struct MacroRoundTripPerson {
    var name: String
    var age: UInt32
    var heightMeters: Double
}

@Test func macroGeneratedRoundTripPoint() throws {
    let original = MacroRoundTripPoint(x: -5, y: 17)
    let data = original.encodeToData()
    let decoded = try MacroRoundTripPoint(decoding: data)
    #expect(decoded.x == -5)
    #expect(decoded.y == 17)
}

@Test func macroGeneratedRoundTripMixedTypes() throws {
    let original = MacroRoundTripPerson(name: "Aria", age: 42, heightMeters: 1.68)
    let data = original.encodeToData()
    let decoded = try MacroRoundTripPerson(decoding: data)
    #expect(decoded.name == "Aria")
    #expect(decoded.age == 42)
    #expect(decoded.heightMeters == 1.68)
}

@Test func macroGeneratedDecodeSkipsUnknownTags() throws {
    // Write a payload that includes an extra tag (3, varint) the decoder doesn't know.
    // The decoder must skip it and still successfully decode tags 1 and 2.
    var writer = WireFormatWriter()
    writer.writeLengthPrefixed { inner in
        inner.writeTag(tag: 1, wireType: .varint)
        Int32(7).encodePayload(into: &inner)
        inner.writeTag(tag: 3, wireType: .varint)        // unknown
        inner.writeVarint(999)
        inner.writeTag(tag: 2, wireType: .varint)
        Int32(11).encodePayload(into: &inner)
    }
    let decoded = try MacroRoundTripPoint(decoding: writer.data)
    #expect(decoded.x == 7)
    #expect(decoded.y == 11)
}

@Test func macroGeneratedDecodeRejectsMissingRequiredField() throws {
    // Encode only tag 1; tag 2 is missing — decoder must throw.
    var writer = WireFormatWriter()
    writer.writeLengthPrefixed { inner in
        inner.writeTag(tag: 1, wireType: .varint)
        Int32(7).encodePayload(into: &inner)
    }
    #expect(throws: WireFormatError.self) {
        _ = try MacroRoundTripPoint(decoding: writer.data)
    }
}
