import Foundation
import Testing
@testable import Wirelet

@Test func tagEncodesWireTypeInLowBits() throws {
    var w = WireFormatWriter()
    w.writeTag(tag: 7, wireType: .lengthDelimited)
    var r = WireFormatReader(data: w.data)
    let (tag, wt) = try r.readTag()
    #expect(tag == 7)
    #expect(wt == .lengthDelimited)
}

@Test func lengthPrefixedRoundTrip() throws {
    var w = WireFormatWriter()
    w.writeLengthPrefixed { inner in
        inner.writeVarint(42)
        inner.writeVarint(43)
    }
    var r = WireFormatReader(data: w.data)
    try r.readLengthPrefixed { inner in
        try #expect(inner.readVarint() == 42)
        try #expect(inner.readVarint() == 43)
    }
}

@Test func skipUnknownLengthDelimited() throws {
    var w = WireFormatWriter()
    w.writeTag(tag: 99, wireType: .lengthDelimited)
    w.writeLengthPrefixed { $0.appendBytes([0xCA, 0xFE]) }
    w.writeTag(tag: 1, wireType: .varint)
    w.writeVarint(7)

    var r = WireFormatReader(data: w.data)
    let (tag1, wt1) = try r.readTag()
    #expect(tag1 == 99 && wt1 == .lengthDelimited)
    try r.skipUnknownField(wireType: wt1)
    let (tag2, _) = try r.readTag()
    #expect(tag2 == 1)
    try #expect(r.readVarint() == 7)
}
