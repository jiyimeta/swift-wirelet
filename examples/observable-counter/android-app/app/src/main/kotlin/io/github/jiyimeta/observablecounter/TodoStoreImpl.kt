package io.github.jiyimeta.observablecounter

/**
 * App-side implementation of the generated `@WireletProvided` `TodoStore`
 * interface. In-memory for the demo; the Swift `TodoListVM` drives it
 * through the generated proxy/adapter over JNI.
 */
class InMemoryTodoStore : TodoStore {
    private val items = mutableListOf<TodoItem>()
    override fun loadAll(): List<TodoItem> = items.toList()
    override fun add(item: TodoItem) { items.add(item) }
    override fun remove(id: Int) { items.removeAll { it.id == id } }
}
