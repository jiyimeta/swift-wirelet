package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Exercises the @WireletProvided injection end to end: a Kotlin TodoStore
 * impl is injected via create(store=), the Swift TodoListVM drives it
 * through the generated proxy/adapter, and the observable StateFlow
 * reflects the writes that went through the Kotlin store.
 */
@RunWith(AndroidJUnit4::class)
class ProvidedRoundTripInstrumentedTest {
    @Test
    fun swiftDrivesInjectedKotlinStore() = runBlocking {
        val store = InMemoryTodoStore()
        val vm = TodoListVMViewModel.create(store = store)

        vm.add(TodoItem(id = 1, title = "from-ui-1", done = false))
        vm.add(TodoItem(id = 2, title = "from-ui-2", done = true))

        // Swift add() wrote through store.add(); items reflects store.loadAll().
        val items = vm.items.first { it.size == 2 }
        assertEquals(2, items.size)
        assertEquals("from-ui-2", items[1].title)
    }

    /**
     * Regression: clear() must write through to the Kotlin store. Previously
     * clear() only emptied the Swift-side array, so the next add() re-hydrated
     * the "cleared" rows from the still-populated store (rows revived +
     * duplicate ids appeared).
     */
    @Test
    fun clearWritesThroughStoreSoAddDoesNotRevive() = runBlocking {
        val store = InMemoryTodoStore()
        val vm = TodoListVMViewModel.create(store = store)

        repeat(5) { i -> vm.add(TodoItem(id = i + 1, title = "task #${i + 1}", done = false)) }
        vm.items.first { it.size == 5 }

        vm.clear()
        val cleared = vm.items.first { it.isEmpty() }
        assertEquals(0, cleared.size)
        assertEquals(0, store.loadAll().size) // store itself is empty, not just the Swift view

        vm.add(TodoItem(id = 1, title = "task #1", done = false))
        val afterAdd = vm.items.first { it.size == 1 }
        assertEquals(1, afterAdd.size) // exactly one row — no revival, no duplicate id=1
        assertEquals(1, afterAdd[0].id)
    }

    /**
     * Regression: setDone() must persist through the store (upsert by id), so a
     * toggle survives the next add()'s re-hydrate instead of being lost.
     */
    @Test
    fun setDonePersistsThroughStoreAcrossAdd() = runBlocking {
        val store = InMemoryTodoStore()
        val vm = TodoListVMViewModel.create(store = store)

        vm.add(TodoItem(id = 1, title = "a", done = false))
        vm.add(TodoItem(id = 2, title = "b", done = false))
        vm.items.first { it.size == 2 }

        vm.setDone(1, true)
        vm.items.first { snapshot -> snapshot.first { it.id == 1 }.done }

        // A later add must not revert id=1's done flag (it lives in the store now).
        vm.add(TodoItem(id = 3, title = "c", done = false))
        val items = vm.items.first { it.size == 3 }
        assertEquals(true, items.first { it.id == 1 }.done)
        assertEquals(3, items.size) // no duplicate from the setDone upsert
    }
}
