import Wirelet
import WireletProvided

@WireFormat
struct TodoItem: Equatable, Sendable {
    var id: Int32
    var title: String
    var done: Bool
}

@WireletProvided
protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}
