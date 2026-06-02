import Observation
import Wirelet
import WireletObservable

/// View-model exposed to the Android app as `TodoListVMViewModel`.
///
/// - `items` mirrors a `StateFlow<List<TodoItem>>` on Kotlin.
/// - `totalCount` mirrors a `StateFlow<Int>`.
/// - `filter` mirrors a `StateFlow<String>`.
/// - `add(_:)`, `clear()`, and `setDone(_:_:)` are bridged as
///   `external fun native*` because they carry `@WireletExpose`.
///
/// Apple builds compile the macros to no-op extensions; only the Android
/// cross-build emits the `@_cdecl` JNI bridges and the `TodoStoreWireletProxy`.
@WireletObservable
@Observable
public final class TodoListVM {
    @ObservationIgnored private let store: TodoStore
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0

    public init(store: TodoStore) {
        self.store = store
        self.items = store.loadAll()
        self.totalCount = Int32(self.items.count)
    }

    @WireletExpose
    public func add(_ item: TodoItem) {
        store.add(item)
        items = store.loadAll()
        totalCount = Int32(items.count)
    }

    @WireletExpose
    public func clear() {
        items.removeAll()
        totalCount = 0
    }

    @WireletExpose
    public func setDone(_ id: Int32, _ done: Bool) {
        items = items.map {
            $0.id == id ? TodoItem(id: $0.id, title: $0.title, done: done) : $0
        }
    }
}
