import Testing
import Foundation
@testable import Wirelet

@WireFormat
struct WithDict {
    var m: [String: Int32]
}

@WireFormat
struct IntKeyDict {
    var m: [Int32: String]
}

@Test func dictionaryRoundTrip() throws {
    let v = WithDict(m: ["a": 1, "b": 2, "c": 3])
    let decoded = try WithDict(decoding: v.encodeToData())
    #expect(decoded.m == ["a": 1, "b": 2, "c": 3])
}

@Test func emptyDictionaryRoundTrip() throws {
    let v = WithDict(m: [:])
    let decoded = try WithDict(decoding: v.encodeToData())
    #expect(decoded.m.isEmpty)
}

@Test func dictionaryCanonicalKeyOrder() {
    // Two dictionaries with the same entries in different literal orders
    // must produce identical wire bytes — entries are canonicalized by
    // sorting on encoded-key bytes before emission.
    var w1 = WireFormatWriter()
    let d1: [String: Int32] = ["banana": 2, "apple": 1, "cherry": 3]
    d1.encodePayload(into: &w1)

    var w2 = WireFormatWriter()
    let d2: [String: Int32] = ["cherry": 3, "apple": 1, "banana": 2]
    d2.encodePayload(into: &w2)

    #expect(w1.data == w2.data)
}

@Test func dictionaryIntKeyRoundTrip() throws {
    let v = IntKeyDict(m: [1: "one", 2: "two", 3: "three"])
    let decoded = try IntKeyDict(decoding: v.encodeToData())
    #expect(decoded.m == [1: "one", 2: "two", 3: "three"])
}
