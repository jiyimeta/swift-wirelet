import Wirelet
import WireletProvided

@WireletProvided
public protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}
