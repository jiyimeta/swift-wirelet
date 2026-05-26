import Testing
import Foundation
@testable import Wirelet

@WireFormatChoice
enum ChoiceRoundTripShape: Equatable {
    case point(Int32, Int32)
    case label(String)
    case empty
}

@Test func choicePointRoundTrip() throws {
    let original: ChoiceRoundTripShape = .point(3, -7)
    let data = original.encodeToData()
    let decoded = try ChoiceRoundTripShape(decoding: data)
    #expect(decoded == .point(3, -7))
}

@Test func choiceLabelRoundTrip() throws {
    let original: ChoiceRoundTripShape = .label("hello")
    let data = original.encodeToData()
    let decoded = try ChoiceRoundTripShape(decoding: data)
    #expect(decoded == .label("hello"))
}

@Test func choiceEmptyRoundTrip() throws {
    let original: ChoiceRoundTripShape = .empty
    let data = original.encodeToData()
    let decoded = try ChoiceRoundTripShape(decoding: data)
    #expect(decoded == .empty)
}

@Test func choiceUnknownDiscriminatorThrows() {
    // Craft a length-prefixed body containing just `varint 99` — outside
    // the declared cases (0/1/2). Reader must throw.
    var writer = WireFormatWriter()
    writer.writeLengthPrefixed { inner in
        inner.writeVarint(99)
    }
    var reader = WireFormatReader(data: writer.data)
    #expect(throws: WireFormatError.self) {
        _ = try ChoiceRoundTripShape(from: &reader)
    }
}

@Test func choiceDecodeSkipsUnknownTagInCasePayload() throws {
    // Encode `.point(3, -7)` then sneak in an unknown tag 5; decoder must skip it.
    var writer = WireFormatWriter()
    writer.writeLengthPrefixed { inner in
        inner.writeVarint(0) // discriminator: .point
        inner.writeTag(tag: 1, wireType: Int32.wireType)
        Int32(3).encodePayload(into: &inner)
        inner.writeTag(tag: 5, wireType: .varint) // unknown
        inner.writeVarint(123)
        inner.writeTag(tag: 2, wireType: Int32.wireType)
        Int32(-7).encodePayload(into: &inner)
    }
    let decoded = try ChoiceRoundTripShape(decoding: writer.data)
    #expect(decoded == .point(3, -7))
}
