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
}
