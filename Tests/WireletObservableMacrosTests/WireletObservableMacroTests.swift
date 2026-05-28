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

final class WireletObservableCompositeExpansionTests: XCTestCase {
    func testWireFormatStructProperty() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class ItemVM {
                var item: TodoItem = TodoItem()
            }
            """,
            expandedSource: """
            @Observable
            final class ItemVM {
                var item: TodoItem = TodoItem()
            }

            extension ItemVM {
                #if os(Android)
                @_cdecl("WireletObservable_ItemVM_item_track")
                public static func __item_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jbyteArray? {
                    guard let env else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as ItemVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.item, on: me) {
                        runnable?.call(method: "run")
                    }
                    return WireletObservableJNI.encode(snapshot, env: env)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }

    func testWireFormatArrayProperty() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class ItemsVM {
                var items: [TodoItem] = []
            }
            """,
            expandedSource: """
            @Observable
            final class ItemsVM {
                var items: [TodoItem] = []
            }

            extension ItemsVM {
                #if os(Android)
                @_cdecl("WireletObservable_ItemsVM_items_track")
                public static func __items_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jbyteArray? {
                    guard let env else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as ItemsVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.items, on: me) {
                        runnable?.call(method: "run")
                    }
                    return WireletObservableJNI.encodeArray(snapshot, env: env)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }

    func testOptionalStringProperty() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class MaybeVM {
                var maybe: String? = nil
            }
            """,
            expandedSource: """
            @Observable
            final class MaybeVM {
                var maybe: String? = nil
            }

            extension MaybeVM {
                #if os(Android)
                @_cdecl("WireletObservable_MaybeVM_maybe_track")
                public static func __maybe_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jbyteArray? {
                    guard let env else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as MaybeVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.maybe, on: me) {
                        runnable?.call(method: "run")
                    }
                    guard let value = snapshot else {
                        return nil
                    }
                    return WireletObservableJNI.encode(value, env: env)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }

    func testOptionalInt32Property() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class NVM {
                var n: Int32? = nil
            }
            """,
            expandedSource: """
            @Observable
            final class NVM {
                var n: Int32? = nil
            }

            extension NVM {
                #if os(Android)
                @_cdecl("WireletObservable_NVM_n_track")
                public static func __n_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jbyteArray? {
                    guard let env else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as NVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.n, on: me) {
                        runnable?.call(method: "run")
                    }
                    guard let value = snapshot else {
                        return nil
                    }
                    return WireletObservableJNI.encode(value, env: env)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }
}
