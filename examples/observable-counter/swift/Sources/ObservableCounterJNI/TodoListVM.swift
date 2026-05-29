import Observation
import Wirelet
import WireletObservable

/// View-model exposed to the Android app as `TodoListVMViewModel`.
///
/// - `items` mirrors a `StateFlow<List<TodoItem>>` on Kotlin.
/// - `totalCount` mirrors a `StateFlow<Int>`.
/// - `filter` mirrors a `StateFlow<String>`.
/// - `add(_:)` and `clear()` are bridged as `external fun nativeAdd(...)`
///   / `nativeClear(...)` because they carry `@WireletExpose`.
///
/// Apple builds compile the macro to a no-op extension; only the Android
/// cross-build emits the `@_cdecl` JNI bridges.
@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0

    public init() {}

    @WireletExpose
    public func add(_ item: TodoItem) {
        items.append(item)
        totalCount += 1
    }

    @WireletExpose
    public func clear() {
        items.removeAll()
        totalCount = 0
    }
}
