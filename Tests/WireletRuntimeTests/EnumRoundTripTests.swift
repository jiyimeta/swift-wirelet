import Foundation
import Testing
@testable import Wirelet

@WireFormatEnum
enum EnumRoundTripColor: UInt8, CaseIterable, Equatable {
    case red, green, blue
}

@WireFormatEnum
enum EnumRoundTripTone: String, CaseIterable, Equatable {
    case major, minor
}

@WireFormat
struct EnumRoundTripAnnotated {
    var color: EnumRoundTripColor
    var name: String
}

@Test func integerRawEnumPayloadRoundTrip() throws {
    for c in EnumRoundTripColor.allCases {
        var writer = WireFormatWriter()
        c.encodePayload(into: &writer)
        var reader = WireFormatReader(data: writer.data)
        let decoded = try EnumRoundTripColor(decodingPayload: &reader)
        #expect(decoded == c)
    }
}

@Test func stringRawEnumPayloadRoundTrip() throws {
    for t in EnumRoundTripTone.allCases {
        var writer = WireFormatWriter()
        t.encodePayload(into: &writer)
        var reader = WireFormatReader(data: writer.data)
        let decoded = try EnumRoundTripTone(decodingPayload: &reader)
        #expect(decoded == t)
    }
}

@Test func enumWireTypeMatchesRawTypeWireType() {
    #expect(EnumRoundTripColor.wireType == UInt8.wireType)
    #expect(EnumRoundTripTone.wireType == String.wireType)
}

@Test func enumInsideStructRoundTrip() throws {
    for c in EnumRoundTripColor.allCases {
        let original = EnumRoundTripAnnotated(color: c, name: "n-\(c)")
        let data = original.encodeToData()
        let decoded = try EnumRoundTripAnnotated(decoding: data)
        #expect(decoded.color == c)
        #expect(decoded.name == "n-\(c)")
    }
}

@Test func unknownEnumRawThrows() throws {
    // Encode UInt8(99) — outside the Color case range.
    var writer = WireFormatWriter()
    UInt8(99).encodePayload(into: &writer)
    var reader = WireFormatReader(data: writer.data)
    #expect(throws: WireFormatError.self) {
        _ = try EnumRoundTripColor(decodingPayload: &reader)
    }
}
