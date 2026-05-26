// Swift-side cross-language conformance suite (Task 2.14).
//
// Each test:
//   1. Reads `<name>.bin` from kotlin/conformance-tests/fixtures/.
//   2. Decodes via the macro-generated `init(decoding:)`.
//   3. Asserts decoded fields match the canonical values.
//   4. Re-encodes and asserts byte-identical to the original `.bin`
//      (proving the Swift side is reproducibly the *source* of the
//      committed bytes).
//
// The Kotlin twin in `kotlin/conformance-tests/.../FixtureRunner.kt`
// does the same loop with generated Kotlin codecs.

import Foundation
import Testing
@testable import Wirelet

private func loadFixture(_ name: String) throws -> Data {
    try Data(contentsOf: FixtureLocator.fixturesURL.appendingPathComponent(name))
}

@Test func primitivesFixtureDecodes() throws {
    let bin = try loadFixture("primitives_v1.bin")
    let v = try Primitives(decoding: bin)
    #expect(v.u32 == 7)
    #expect(v.i32 == -3)
    #expect(v.f == 1.5)
    #expect(v.d == 2.25)
    #expect(v.s == "hi")
    #expect(v.b == true)
    let reencoded = v.encodeToData()
    #expect(reencoded == bin)
}

@Test func optionalPresentFixture() throws {
    let bin = try loadFixture("optional_present_v1.bin")
    let v = try OptionalHolder(decoding: bin)
    #expect(v.a == 5)
    #expect(v.b == 42)
    #expect(v.encodeToData() == bin)
}

@Test func optionalAbsentFixture() throws {
    let bin = try loadFixture("optional_absent_v1.bin")
    let v = try OptionalHolder(decoding: bin)
    #expect(v.a == 5)
    #expect(v.b == nil)
    #expect(v.encodeToData() == bin)
}

@Test func choiceFixture() throws {
    let bin = try loadFixture("choice_v1.bin")
    let v = try ShapeChoice(decoding: bin)
    #expect(v == .point(3, -7))
    #expect(v.encodeToData() == bin)
}

@Test func forwardCompatV2ToV1() throws {
    // Bytes were produced by OptionalHolderV2 (a, b, c). Decoding with
    // v1's schema must silently skip tag 3 (`c`) and recover (a, b).
    // No byte-equal re-encode check: the v1 re-encode lacks tag 3 by
    // definition.
    let bin = try loadFixture("forward_compat_v2_to_v1.bin")
    let v = try OptionalHolder(decoding: bin)
    #expect(v.a == 5)
    #expect(v.b == 42)
}
