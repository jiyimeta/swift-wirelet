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
        // Write through the injected Kotlin store (the source of truth) — a
        // Swift-only `items.removeAll()` would leave the store populated, so
        // the next `add` would re-hydrate the "cleared" rows from Kotlin.
        for item in store.loadAll() {
            store.remove(item.id)
        }
        items = store.loadAll()
        totalCount = Int32(items.count)
    }

    @WireletExpose
    public func setDone(_ id: Int32, _ done: Bool) {
        // Write the toggle through the store (upsert by id) so it survives the
        // next `add`'s re-hydrate; a Swift-only mutation would be lost.
        guard let existing = store.loadAll().first(where: { $0.id == id }) else { return }
        store.add(TodoItem(id: existing.id, title: existing.title, done: done))
        items = store.loadAll()
        totalCount = Int32(items.count)
    }
}
