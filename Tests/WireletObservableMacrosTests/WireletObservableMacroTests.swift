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

    func testUnsupportedExposedMethodSignatureRaisesDiagnostic() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class Multi {
                @WireletExpose
                public func twoArgs(_ a: Int32, _ b: Int32) {}
            }
            """,
            expandedSource: """
            @Observable
            final class Multi {
                public func twoArgs(_ a: Int32, _ b: Int32) {}
            }

            extension Multi {
                #if os(Android)
                @_cdecl("WireletObservable_Multi_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(Multi())
                }
                @_cdecl("WireletObservable_Multi_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: Multi.self)
                }
                #endif
            }
            """,
            diagnostics: [
                .init(
                    message: "@WireletExpose only supports zero-arg methods or a single @WireFormat argument in Phase 1.",
                    line: 5,
                    column: 17
                ),
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
                @_cdecl("WireletObservable_CounterVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(CounterVM())
                }
                @_cdecl("WireletObservable_CounterVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: CounterVM.self)
                }
                @_cdecl("WireletObservable_CounterVM_count_set")
                public static func __count_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jint
                ) {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    me.count = Int32(new_value)
                }
                @_cdecl("WireletObservable_CounterVM_active_set")
                public static func __active_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jboolean
                ) {
                    let me = WireletObservableJNI.unwrap(self_ptr) as CounterVM
                    me.active = (new_value != 0)
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
                @_cdecl("WireletObservable_ItemVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(ItemVM())
                }
                @_cdecl("WireletObservable_ItemVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: ItemVM.self)
                }
                @_cdecl("WireletObservable_ItemVM_item_set")
                public static func __item_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jbyteArray?
                ) {
                    guard let env, let new_value else {
                        return
                    }
                    let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
                    guard let decoded = try? TodoItem(decoding: data) else {
                        return
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as ItemVM
                    me.item = decoded
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
                @_cdecl("WireletObservable_ItemsVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(ItemsVM())
                }
                @_cdecl("WireletObservable_ItemsVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: ItemsVM.self)
                }
                @_cdecl("WireletObservable_ItemsVM_items_set")
                public static func __items_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jbyteArray?
                ) {
                    guard let env, let new_value else {
                        return
                    }
                    let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
                    var reader = WireFormatReader(data: data)
                    guard let count = try? reader.readVarint() else {
                        return
                    }
                    var elements: [TodoItem] = []
                    elements.reserveCapacity(Int(count))
                    for _ in 0 ..< Int(count) {
                        guard let element = try? TodoItem(from: &reader) else {
                            return
                        }
                        elements.append(element)
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as ItemsVM
                    me.items = elements
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
                @_cdecl("WireletObservable_MaybeVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(MaybeVM())
                }
                @_cdecl("WireletObservable_MaybeVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: MaybeVM.self)
                }
                @_cdecl("WireletObservable_MaybeVM_maybe_set")
                public static func __maybe_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jstring?
                ) {
                    let me = WireletObservableJNI.unwrap(self_ptr) as MaybeVM
                    guard let env, let envValue = env.pointee, let new_value else {
                        me.maybe = nil
                        return
                    }
                    let cstr = envValue.pointee.GetStringUTFChars(env, new_value, nil)
                    defer {
                        envValue.pointee.ReleaseStringUTFChars(env, new_value, cstr)
                    }
                    guard let cstr else {
                        return
                    }
                    me.maybe = String(cString: cstr)
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
                @_cdecl("WireletObservable_NVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(NVM())
                }
                @_cdecl("WireletObservable_NVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: NVM.self)
                }
                @_cdecl("WireletObservable_NVM_n_set")
                public static func __n_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jbyteArray?
                ) {
                    let me = WireletObservableJNI.unwrap(self_ptr) as NVM
                    guard let env, let new_value else {
                        me.n = nil
                        return
                    }
                    let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
                    guard let decoded = try? Int32(decoding: data) else {
                        return
                    }
                    me.n = decoded
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }
}

// MARK: - Group J: Constructor, Destructor, Setters, and @WireletExpose Invoke bridges

final class WireletObservableConstructorAndInvokeTests: XCTestCase {

    /// Verifies that a minimal mutable class with a String property emits
    /// __label_track_jni (pre-existing), __label_set_jni, __new_jni, and __release_jni.
    func testNewReleaseAndStringSetter() {
        assertMacroExpansion(
            """
            @WireletObservable
            @Observable
            final class LabelVM {
                var label: String = ""
            }
            """,
            expandedSource: """
            @Observable
            final class LabelVM {
                var label: String = ""
            }

            extension LabelVM {
                #if os(Android)
                @_cdecl("WireletObservable_LabelVM_label_track")
                public static func __label_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jstring? {
                    guard let env, let envValue = env.pointee else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as LabelVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.label, on: me) {
                        runnable?.call(method: "run")
                    }
                    return snapshot.withCString { cstr in
                        envValue.pointee.NewStringUTF(env, cstr)
                    }
                }
                @_cdecl("WireletObservable_LabelVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(LabelVM())
                }
                @_cdecl("WireletObservable_LabelVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: LabelVM.self)
                }
                @_cdecl("WireletObservable_LabelVM_label_set")
                public static func __label_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jstring?
                ) {
                    guard let env, let envValue = env.pointee, let new_value else {
                        return
                    }
                    let cstr = envValue.pointee.GetStringUTFChars(env, new_value, nil)
                    defer {
                        envValue.pointee.ReleaseStringUTFChars(env, new_value, cstr)
                    }
                    guard let cstr else {
                        return
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as LabelVM
                    me.label = String(cString: cstr)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }

    /// Verifies that a @WireletExpose method with a single @WireFormat argument
    /// emits __add_invoke_jni with the one-arg decode path.
    func testWireFormatExposeMethod() {
        assertMacroExpansion(
            """
            struct TodoItem { var id: Int32 }
            @WireletObservable
            @Observable
            final class TodoListVM {
                var items: [TodoItem] = []
                @WireletExpose public func add(_ item: TodoItem) {
                    items.append(item)
                }
            }
            """,
            expandedSource: """
            struct TodoItem { var id: Int32 
            }
            @Observable
            final class TodoListVM {
                var items: [TodoItem] = []
                public func add(_ item: TodoItem) {
                    items.append(item)
                }
            }

            extension TodoListVM {
                #if os(Android)
                @_cdecl("WireletObservable_TodoListVM_items_track")
                public static func __items_track_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ on_change: jobject?
                ) -> jbyteArray? {
                    guard let env else {
                        return nil
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as TodoListVM
                    let runnable = JObject(env: env, jobject: on_change)
                    let snapshot = ObservationTrackingHelper.read(\\.items, on: me) {
                        runnable?.call(method: "run")
                    }
                    return WireletObservableJNI.encodeArray(snapshot, env: env)
                }
                @_cdecl("WireletObservable_TodoListVM_new")
                public static func __new_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?
                ) -> jlong {
                    return WireletObservableJNI.retain(TodoListVM())
                }
                @_cdecl("WireletObservable_TodoListVM_release")
                public static func __release_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong
                ) {
                    WireletObservableJNI.release(self_ptr, as: TodoListVM.self)
                }
                @_cdecl("WireletObservable_TodoListVM_items_set")
                public static func __items_set_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ new_value: jbyteArray?
                ) {
                    guard let env, let new_value else {
                        return
                    }
                    let data = WireletObservableJNI.dataFromByteArray(new_value, env: env)
                    var reader = WireFormatReader(data: data)
                    guard let count = try? reader.readVarint() else {
                        return
                    }
                    var elements: [TodoItem] = []
                    elements.reserveCapacity(Int(count))
                    for _ in 0 ..< Int(count) {
                        guard let element = try? TodoItem(from: &reader) else {
                            return
                        }
                        elements.append(element)
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as TodoListVM
                    me.items = elements
                }
                @_cdecl("WireletObservable_TodoListVM_add_invoke")
                public static func __add_invoke_jni(
                    _ env: UnsafeMutablePointer<JNIEnv?>?,
                    _ self_ptr: jlong,
                    _ arg0: jbyteArray?
                ) {
                    guard let env, let arg0 else {
                        return
                    }
                    let data = WireletObservableJNI.dataFromByteArray(arg0, env: env)
                    guard let decoded = try? TodoItem(decoding: data) else {
                        return
                    }
                    let me = WireletObservableJNI.unwrap(self_ptr) as TodoListVM
                    me.add(decoded)
                }
                #endif
            }
            """,
            macros: macroSpecs
        )
    }
}
