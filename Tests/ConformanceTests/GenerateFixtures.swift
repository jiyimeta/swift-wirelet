// Disabled-by-default fixture regenerator (Task 2.14).
//
// To regenerate the cross-language conformance fixtures:
//   1. Remove the `.disabled(...)` trait below (or pass --filter and the
//      `WIRELET_REGEN_FIXTURES` env var as documented).
//   2. `swift test --filter ConformanceTests.regenerateFixtures`
//   3. Restore the disable marker.
//   4. Inspect the resulting `.bin` / `.json` files, commit them.
//
// The accompanying `.json` files are the canonical human-readable
// "answer key" — they're hand-authored once and committed alongside
// the bytes. The conformance runners decode the bytes and assert the
// fields match the answer key, then re-encode and assert byte-equal
// against the bytes. JSON is descriptive, the bytes are the contract.

import Foundation
import Testing
@testable import Wirelet

@Test(.disabled("Run manually to regenerate fixtures"))
func regenerateFixtures() throws {
    let dir = FixtureLocator.fixturesURL
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // ------- primitives_v1 -------
    let prim = Primitives(u32: 7, i32: -3, f: 1.5, d: 2.25, s: "hi", b: true)
    try prim.encodeToData().write(to: dir.appendingPathComponent("primitives_v1.bin"))
    try #"{"u32":7,"i32":-3,"f":1.5,"d":2.25,"s":"hi","b":true}"#
        .write(to: dir.appendingPathComponent("primitives_v1.json"),
               atomically: true, encoding: .utf8)

    // ------- optional_present_v1 -------
    let optPresent = OptionalHolder(a: 5, b: 42)
    try optPresent.encodeToData()
        .write(to: dir.appendingPathComponent("optional_present_v1.bin"))
    try #"{"a":5,"b":42}"#
        .write(to: dir.appendingPathComponent("optional_present_v1.json"),
               atomically: true, encoding: .utf8)

    // ------- optional_absent_v1 -------
    let optAbsent = OptionalHolder(a: 5, b: nil)
    try optAbsent.encodeToData()
        .write(to: dir.appendingPathComponent("optional_absent_v1.bin"))
    try #"{"a":5,"b":null}"#
        .write(to: dir.appendingPathComponent("optional_absent_v1.json"),
               atomically: true, encoding: .utf8)

    // ------- choice_v1 -------
    let choice = ShapeChoice.point(3, -7)
    try choice.encodeToData()
        .write(to: dir.appendingPathComponent("choice_v1.bin"))
    try #"{"kind":"point","args":[3,-7]}"#
        .write(to: dir.appendingPathComponent("choice_v1.json"),
               atomically: true, encoding: .utf8)

    // ------- forward_compat_v2_to_v1 -------
    // v2 encodes (a, b, c); decoded with v1's schema, tag 3 is skipped.
    let v2 = OptionalHolderV2(a: 5, b: 42, c: "extra")
    try v2.encodeToData()
        .write(to: dir.appendingPathComponent("forward_compat_v2_to_v1.bin"))
    try #"{"a":5,"b":42}"#
        .write(to: dir.appendingPathComponent("forward_compat_v2_to_v1.json"),
               atomically: true, encoding: .utf8)

    // ------- map_multi_v1 -------
    // Multi-entry Map; entries are canonicalised by encoded-key bytes
    // (lexicographic), so the wire bytes are deterministic regardless of
    // Dictionary's intrinsic unordered iteration. The Kotlin emitter must
    // produce identical bytes (sorted via `ByteArrayLexComparator`).
    let mapMulti = MapHolder(m: ["zeta": -1, "alpha": 10, "mango": 7])
    try mapMulti.encodeToData()
        .write(to: dir.appendingPathComponent("map_multi_v1.bin"))
    try #"{"m":{"alpha":10,"mango":7,"zeta":-1}}"#
        .write(to: dir.appendingPathComponent("map_multi_v1.json"),
               atomically: true, encoding: .utf8)
}
