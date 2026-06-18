import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import WireletMacros
import XCTest

private let testMacros: [String: Macro.Type] = [
    "WireFormatChoice": WireFormatChoiceMacro.self,
]

private let singleCaseSource = """
@WireFormatChoice
enum E {
    case a
}
"""

private let singleCaseExpanded = """
enum E {
    case a
}

extension E: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        switch self {
        case .a:
            writer.writeVarint(UInt64(0))
        }
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        let disc = try reader.readVarint()
        switch disc {
        case 0:
            self = .a
        default:
            throw WireFormatError.unknownChoiceDiscriminator(UInt32(truncatingIfNeeded: disc))
        }
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

private let singleCaseDiagnosticMessage =
    "@WireFormatChoice expects at least one case with associated values; prefer @WireFormatEnum for plain enums"

private let twoArgCaseSource = """
@WireFormatChoice
enum E {
    case point(Int32, Int32)
}
"""

private let twoArgCaseExpanded = """
enum E {
    case point(Int32, Int32)
}

extension E: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        switch self {
        case .point(let v0, let v1):
            writer.writeVarint(UInt64(0))
            writer.writeTag(tag: 1, wireType: Int32.wireType)
            v0.encode(into: &writer)
            writer.writeTag(tag: 2, wireType: Int32.wireType)
            v1.encode(into: &writer)
        }
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        let disc = try reader.readVarint()
        switch disc {
        case 0:
            var _arg0: Int32? = nil
            var _arg1: Int32? = nil
            while !reader.isAtEnd {
                let (tag, wt) = try reader.readTag()
                switch tag {
                case 1:
                    _arg0 = try Int32(from: &reader)
                case 2:
                    _arg1 = try Int32(from: &reader)
                default:
                    try reader.skipUnknownField(wireType: wt)
                }
            }
            guard let _arg0 else {
                throw WireFormatError.unknownTag(tag: 1, wireType: Int32.wireType)
            }
            guard let _arg1 else {
                throw WireFormatError.unknownTag(tag: 2, wireType: Int32.wireType)
            }
            self = .point(_arg0, _arg1)
        default:
            throw WireFormatError.unknownChoiceDiscriminator(UInt32(truncatingIfNeeded: disc))
        }
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

private let mixedCasesSource = """
@WireFormatChoice
enum Shape {
    case point(Int32, Int32)
    case label(String)
    case empty
}
"""

private let mixedCasesExpanded = """
enum Shape {
    case point(Int32, Int32)
    case label(String)
    case empty
}

extension Shape: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        switch self {
        case .point(let v0, let v1):
            writer.writeVarint(UInt64(0))
            writer.writeTag(tag: 1, wireType: Int32.wireType)
            v0.encode(into: &writer)
            writer.writeTag(tag: 2, wireType: Int32.wireType)
            v1.encode(into: &writer)
        case .label(let v0):
            writer.writeVarint(UInt64(1))
            writer.writeTag(tag: 1, wireType: String.wireType)
            v0.encode(into: &writer)
        case .empty:
            writer.writeVarint(UInt64(2))
        }
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        let disc = try reader.readVarint()
        switch disc {
        case 0:
            var _arg0: Int32? = nil
            var _arg1: Int32? = nil
            while !reader.isAtEnd {
                let (tag, wt) = try reader.readTag()
                switch tag {
                case 1:
                    _arg0 = try Int32(from: &reader)
                case 2:
                    _arg1 = try Int32(from: &reader)
                default:
                    try reader.skipUnknownField(wireType: wt)
                }
            }
            guard let _arg0 else {
                throw WireFormatError.unknownTag(tag: 1, wireType: Int32.wireType)
            }
            guard let _arg1 else {
                throw WireFormatError.unknownTag(tag: 2, wireType: Int32.wireType)
            }
            self = .point(_arg0, _arg1)
        case 1:
            var _arg0: String? = nil
            while !reader.isAtEnd {
                let (tag, wt) = try reader.readTag()
                switch tag {
                case 1:
                    _arg0 = try String(from: &reader)
                default:
                    try reader.skipUnknownField(wireType: wt)
                }
            }
            guard let _arg0 else {
                throw WireFormatError.unknownTag(tag: 1, wireType: String.wireType)
            }
            self = .label(_arg0)
        case 2:
            self = .empty
        default:
            throw WireFormatError.unknownChoiceDiscriminator(UInt32(truncatingIfNeeded: disc))
        }
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

final class WireFormatChoiceMacroExpansionTests: XCTestCase {
    func testSingleCaseNoAssociatedValuesExpansion() {
        assertMacroExpansion(
            singleCaseSource,
            expandedSource: singleCaseExpanded,
            diagnostics: [
                DiagnosticSpec(
                    message: singleCaseDiagnosticMessage,
                    line: 1,
                    column: 1,
                    severity: .warning,
                ),
            ],
            macros: testMacros,
        )
    }

    func testTwoArgCaseExpansion() {
        assertMacroExpansion(
            twoArgCaseSource,
            expandedSource: twoArgCaseExpanded,
            macros: testMacros,
        )
    }

    func testMixedCasesExpansion() {
        assertMacroExpansion(
            mixedCasesSource,
            expandedSource: mixedCasesExpanded,
            macros: testMacros,
        )
    }
}
