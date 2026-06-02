package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * De-risks the `[String]` (array-of-primitive) `@WireletExpose` argument
 * bridge. `addTitles(List<String>)` crosses the JNI boundary as a
 * `WireletList.encodeStrings`-encoded ByteArray; the Swift side decodes it as
 * `[String]` and adds one todo per title. If the wire format is wrong the
 * snapshot comes back empty, short, or with garbled titles.
 */
@RunWith(AndroidJUnit4::class)
class StringListArgInstrumentedTest {

    @Test
    fun addTitlesRoundTrips() = runBlocking {
        val vm = TodoListVMViewModel.create(store = InMemoryTodoStore())
        val titles = listOf("alpha", "beta", "gamma", "マルチバイト")
        vm.addTitles(titles)
        val items = vm.items.first { snapshot -> snapshot.size == titles.size }
        assertEquals(titles, items.map { it.title })
        val total = vm.totalCount.first { it == titles.size }
        assertEquals(titles.size, total)
    }
}
