import Foundation
import Testing
import WireletObservableSwiftBridgesEmitter

// MARK: - Golden-file tests for @WireletExpose invoke & return bridges

@Suite("SwiftBridgesInvokeEmitterTests")
struct SwiftBridgesInvokeEmitterTests {
    // MARK: - Multi-arg invoke bridge

    @Test func multiArgInvokeBridge() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func setDone(_ id: Int32, _ done: Bool) {}
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)

        #expect(bridges.contains("@_cdecl(\"WireletObservable_Demo_setDone_invoke\")"))
        #expect(bridges.contains("public func __Demo_setDone_invoke_jni("))
        #expect(bridges.contains("_ arg0: jint"))
        #expect(bridges.contains("_ arg1: jboolean"))
        #expect(bridges.contains("let decoded0 = Int32(arg0)"))
        #expect(bridges.contains("let decoded1 = (arg1 != 0)"))
        #expect(bridges.contains("me.setDone(decoded0, decoded1)"))
    }

    /// Regression: a method with two *env-using* arguments (e.g. two Strings)
    /// must unwrap `env`/`envValue` ONCE at the top, not re-`guard let env`
    /// per argument. The optional `env` parameter, re-bound in the first
    /// decode block, would otherwise be non-optional for the second — and the
    /// second `guard let env` would fail to compile.
    @Test func multiArgStringInvokeBridgeHoistsEnvUnwrap() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func rename(_ id: String, _ name: String) {}
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "rename_invoke").last ?? ""

        // Exactly one env unwrap for the whole method (hoisted), not one per arg.
        #expect(invoke.components(separatedBy: "guard let env").count - 1 == 1)
        #expect(invoke.contains("guard let env, let envValue = env.pointee else {"))
        // Each argument still guards its own raw jstring.
        #expect(invoke.contains("guard let raw0 = arg0 else {"))
        #expect(invoke.contains("guard let raw1 = arg1 else {"))
        #expect(invoke.contains("me.rename(decoded0, decoded1)"))
    }

    /// Regression: String + [String] (the shape used by Folino's
    /// `bulkAddToPlaylist(_ playlistId: String, _ scoreIds: [String])`).
    @Test func multiArgStringAndArrayInvokeBridgeHoistsEnvUnwrap() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func bulkAdd(_ playlistId: String, _ scoreIds: [String]) {}
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "bulkAdd_invoke").last ?? ""

        #expect(invoke.components(separatedBy: "guard let env").count - 1 == 1)
        #expect(invoke.contains("guard let raw0 = arg0 else {"))
        #expect(invoke.contains("guard let raw1 = arg1 else {"))
        #expect(invoke.contains("WireFormatReader"))
        #expect(invoke.contains("me.bulkAdd(decoded0, decoded1)"))
    }

    // MARK: - Return-value invoke bridges

    @Test func stringReturnInvokeBridge() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func describe() -> String { "" }
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "describe_invoke").last ?? ""

        #expect(invoke.contains(") -> jstring? {"))
        #expect(invoke.contains("guard let env, let envValue = env.pointee else {"))
        #expect(invoke.contains("return nil"))
        #expect(invoke.contains("me.describe()"))
        #expect(invoke.contains("NewStringUTF"))
    }

    @Test func primitiveReturnInvokeBridge() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func count() -> Int32 { 0 }
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "count_invoke").last ?? ""

        #expect(invoke.contains(") -> jint {"))
        #expect(invoke.contains("return jint(me.count())"))
        // No env unwrap needed for a pure primitive return.
        #expect(!invoke.components(separatedBy: "me.count()")[0].contains("guard let env"))
    }

    @Test func boolReturnInvokeBridge() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func ready() -> Bool { true }
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "ready_invoke").last ?? ""

        #expect(invoke.contains(") -> jboolean {"))
        #expect(invoke.contains("(me.ready()) ? 1 : 0"))
    }

    @Test func arrayReturnInvokeBridge() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func export(_ id: String) -> [TodoItem] { [] }
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let invoke = bridges.components(separatedBy: "export_invoke").last ?? ""

        #expect(invoke.contains(") -> jbyteArray? {"))
        #expect(invoke.contains("WireletObservableJNI.encodeArray(me.export(decoded0), env: env)"))
        #expect(invoke.contains("guard let raw0 = arg0 else {"))
    }

    @Test func voidReturnInvokeBridgeHasNoReturnClause() throws {
        let source = """
        import Observation
        import WireletObservable

        @WireletObservable
        @Observable
        public final class Demo {
            @WireletExpose
            public func noop() {}
        }
        """
        let url = try writeEmitterTmp(name: "Demo.swift", content: source)
        let results = try SwiftBridgesEmitter().emit(sources: [url])
        let bridges = try #require(results.first(where: { $0.name.hasSuffix("Demo+JNIBridges.swift") })?.content)
        let beforeCall = bridges.components(separatedBy: "noop_invoke_jni(")[1].components(separatedBy: "me.noop()")[0]
        #expect(!beforeCall.contains("->"))
        #expect(bridges.contains("me.noop()"))
    }
}
