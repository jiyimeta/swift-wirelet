/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0
    public var pinned: TodoItem? = nil

    @ObservationIgnored
    public var debugLabel: String = ""

    public static let configKey: String = "todoList"

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

    public func unmarkedHelper() {
        // not @WireletExpose — must be skipped
    }
}
