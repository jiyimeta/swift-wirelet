package io.github.jiyimeta.observablecounter

/**
 * App-side implementation of the generated `@WireletProvided` `TodoStore`
 * interface. In-memory for the demo; the Swift `TodoListVM` drives it
 * through the generated proxy/adapter over JNI.
 */
class InMemoryTodoStore : TodoStore {
    private val items = mutableListOf<TodoItem>()
    override fun loadAll(): List<TodoItem> = items.toList()

    /** Upsert by id: replace in place (keeps order, used by setDone's
     *  write-through) or append a new row. */
    override fun add(item: TodoItem) {
        val idx = items.indexOfFirst { it.id == item.id }
        if (idx >= 0) items[idx] = item else items.add(item)
    }

    override fun remove(id: Int) { items.removeAll { it.id == id } }
}
