import Foundation
import Testing
@testable import WireletSchema

@Test func parsesSimpleStruct() throws {
    let fixtureURL = try #require(Bundle.module.url(
        forResource: "SimpleStruct",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: fixtureURL, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "SimpleStruct.swift")

    #expect(schema.types.count == 1)
    guard case let .struct(s) = schema.types[0] else {
        Issue.record("Expected struct, got \(schema.types[0])")
        return
    }
    #expect(s.name == "PointWire")
    #expect(s.fields == [
        WireField(name: "x", typeText: "Int32", tag: 1),
        WireField(name: "y", typeText: "Int32", tag: 2),
    ])
    #expect(s.kotlinTarget == .auto)
}

/// A default value on the declaration is the authoring gesture that marks an appended
/// field as safe for hosts that predate it, so the parser has to carry it through to
/// the schema verbatim — the emitter is the only layer that can spell it in Kotlin.
@Test func parsesDeclaredDefaultValues() {
    let source = """
    @WireFormat
    public struct OptionsWire {
        public var mode: Int32
        public var showsLyrics: UInt8 = 1
        public var label: String = "none"
    }
    """

    let schema = SchemaParser.parse(source: source, fileName: "OptionsWire.swift")

    guard case let .struct(s) = schema.types[0] else {
        Issue.record("Expected struct, got \(schema.types[0])")
        return
    }
    #expect(s.fields == [
        WireField(name: "mode", typeText: "Int32", tag: 1),
        WireField(name: "showsLyrics", typeText: "UInt8", tag: 2, defaultLiteral: "1"),
        WireField(name: "label", typeText: "String", tag: 3, defaultLiteral: "\"none\""),
    ])
}

@Test func parsesChoiceEnum() throws {
    let url = try #require(Bundle.module.url(
        forResource: "ChoiceEnum",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "ChoiceEnum.swift")

    #expect(schema.types.count == 1)
    guard case let .choice(c) = schema.types[0] else {
        Issue.record("Expected choice, got \(schema.types[0])")
        return
    }
    #expect(c.name == "ScoreCursorWire")
    #expect(c.cases == [
        WireChoiceCase(name: "item", payload: [
            PayloadField(label: nil, typeText: "ScoreItemIDWire"),
        ]),
        WireChoiceCase(name: "beat", payload: [
            PayloadField(label: "measureIndex", typeText: "Int32"),
            PayloadField(label: "tickInMeasure", typeText: "Int32"),
        ]),
    ])
}

@Test func parsesRawEnum() throws {
    let url = try #require(Bundle.module.url(
        forResource: "RawEnum",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "RawEnum.swift")

    #expect(schema.types.count == 1)
    guard case let .rawEnum(e) = schema.types[0] else {
        Issue.record("Expected rawEnum, got \(schema.types[0])")
        return
    }
    #expect(e.name == "GMInstrumentFamilyWire")
    #expect(e.cases == ["piano", "chromaticPercussion", "organ"])
}

@Test func parsesNestedStruct() throws {
    let url = try #require(Bundle.module.url(
        forResource: "NestedStruct",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "NestedStruct.swift")

    #expect(schema.types.count == 1)
    guard case let .struct(s) = schema.types[0] else {
        Issue.record("Expected struct, got \(schema.types[0])")
        return
    }
    #expect(s.name == "DecodedFrame")
    #expect(s.fields == [
        WireField(name: "x", typeText: "Double", tag: 1),
        WireField(name: "y", typeText: "Double", tag: 2),
    ])
}

@Test func parsesTagAssignmentAndOptional() throws {
    let url = try #require(Bundle.module.url(
        forResource: "TaggedStruct",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "TaggedStruct.swift")

    #expect(schema.types.count == 1)
    guard case let .struct(s) = schema.types[0] else {
        Issue.record("Expected struct, got \(schema.types[0])")
        return
    }
    #expect(s.name == "TaggedRecord")
    #expect(s.reservedTags == [2, 4])
    #expect(s.fields == [
        WireField(name: "a", typeText: "Int32", tag: 1),
        WireField(name: "b", typeText: "Int32", tag: 7),
        WireField(name: "c", typeText: "Int32?", wrappedTypeText: "Int32", isOptional: true, tag: 3),
        WireField(name: "d", typeText: "Int32", tag: 5),
    ])
}

@Test func parsesKotlinTargetOverrides() throws {
    let url = try #require(Bundle.module.url(
        forResource: "KotlinTargetOverrides",
        withExtension: "swift",
        subdirectory: "Fixtures",
    ))
    let source = try String(contentsOf: url, encoding: .utf8)

    let schema = SchemaParser.parse(source: source, fileName: "KotlinTargetOverrides.swift")

    #expect(schema.types.count == 3)
    #expect(schema.types[0].kotlinTarget == .skip)
    #expect(schema.types[1].kotlinTarget == .explicit("io.example.legacy.Frame"))
    #expect(schema.types[2].kotlinTarget == .skip)
}
