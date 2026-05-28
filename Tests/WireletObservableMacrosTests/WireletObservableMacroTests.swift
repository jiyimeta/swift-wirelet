import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletObservableMacros

private let macroSpecs: [String: any Macro.Type] = [
    "WireletObservable": WireletObservableMacro.self,
    "WireletExpose": WireletExposeMacro.self,
]

final class WireletObservableMacroDiagnosticsTests: XCTestCase {
    func testNonFinalClassEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            @Observable
            class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable requires a final class.", line: 3, column: 7),
            ],
            macros: macroSpecs
        )
    }

    func testMissingObservableEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            final class Foo {
                var x: Int32 = 0
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int32 = 0
            }
            """,
            diagnostics: [
                .init(message: "@WireletObservable must be paired with @Observable.", line: 2, column: 13),
            ],
            macros: macroSpecs
        )
    }
}

final class WireletObservablePrimitiveExpansionTests: XCTestCase {
    func testInt32AndBoolStoredProperties() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class CounterVM {
                var count: Int32 = 0
                var active: Bool = false
            }
            """,
            expandedSource: """
            @Observable
            final class CounterVM {
                var count: Int32 = 0
                var active: Bool = false
            }

            extension CounterVM {
                #if os(Android)
                @_cdecl("WireletObservable_CounterVM_count_track")
                public static func __count_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jint {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.count, on: me) {
                        runnable?.call(method: "run")
                    }
                    return jint(snapshot)
                }
                @_cdecl("WireletObservable_CounterVM_active_track")
                public static func __active_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jboolean {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.active, on: me) {
                        runnable?.call(method: "run")
                    }
                    return jboolean(snapshot ? 1 : 0)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }
}
