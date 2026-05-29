import Testing
@testable import WireletObservableSchema

@Suite struct InvokeArgClassifierTests {
    @Test func primitiveInt32() {
        let kind = InvokeArgClassifier.classify("Int32")
        #expect(kind == .primitive(jniSwiftType: "jint", swiftCast: "Int32"))
    }

    @Test func primitiveBool() {
        let kind = InvokeArgClassifier.classify("Bool")
        #expect(kind == .bool)
    }

    @Test func primitiveInt64() {
        let kind = InvokeArgClassifier.classify("Int64")
        #expect(kind == .primitive(jniSwiftType: "jlong", swiftCast: "Int64"))
    }

    @Test func primitiveFloat() {
        let kind = InvokeArgClassifier.classify("Float")
        #expect(kind == .primitive(jniSwiftType: "jfloat", swiftCast: "Float"))
    }

    @Test func string() {
        let kind = InvokeArgClassifier.classify("String")
        #expect(kind == .string)
    }

    @Test func wireFormatStruct() {
        let kind = InvokeArgClassifier.classify("TodoItem")
        #expect(kind == .wireFormat(typeName: "TodoItem"))
    }

    @Test func optionalPrimitive() {
        let kind = InvokeArgClassifier.classify("Int32?")
        #expect(kind == .optionalPrimitive(innerTypeName: "Int32"))
    }

    @Test func optionalString() {
        let kind = InvokeArgClassifier.classify("String?")
        #expect(kind == .optionalString)
    }

    @Test func optionalWireFormat() {
        let kind = InvokeArgClassifier.classify("TodoItem?")
        #expect(kind == .optionalWireFormat(typeName: "TodoItem"))
    }

    @Test func arrayOfWireFormat() {
        let kind = InvokeArgClassifier.classify("[TodoItem]")
        #expect(kind == .array(elementTypeName: "TodoItem"))
    }
}
