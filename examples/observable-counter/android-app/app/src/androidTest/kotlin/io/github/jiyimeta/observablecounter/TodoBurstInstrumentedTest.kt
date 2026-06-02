package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Drives 10 sequential add() calls against a single VM and asserts the
 * StateFlow snapshot reflects all 10 mutations. If the JNI bridge round
 * trip is broken, items either hangs, comes back empty, or has fewer
 * elements than mutations.
 */
@RunWith(AndroidJUnit4::class)
class TodoBurstInstrumentedTest {

    @Test
    fun addBurstReachesExpectedSnapshot() = runBlocking {
        val vm = TodoListVMViewModel.create(store = InMemoryTodoStore())
        repeat(10) { i ->
            vm.add(TodoItem(id = i + 1, title = "task #${i + 1}", done = false))
        }
        val finalItems = vm.items.first { snapshot -> snapshot.size == 10 }
        assertEquals(10, finalItems.size)
        finalItems.forEachIndexed { idx, item ->
            assertEquals((idx + 1), item.id)
            assertEquals("task #${idx + 1}", item.title)
            assertEquals(false, item.done)
        }
        val finalTotal = vm.totalCount.first { it == 10 }
        assertEquals(10, finalTotal)
    }
}
