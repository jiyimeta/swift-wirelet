package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Drives a Swift -> Kotlin round trip through the generalized JObject:
 * Swift adds two TodoItems and removes one via the Kotlin adapter, then
 * reads the list back and returns its count. Proves jbyteArray-arg,
 * jint-arg, and jbyteArray-return marshaling across the boundary.
 */
@RunWith(AndroidJUnit4::class)
class ProvidedRoundTripInstrumentedTest {

    @Test
    fun swiftDrivesKotlinStore() {
        val impl = InMemoryTodoStore()
        val adapter = TodoStoreNativeAdapter(impl)

        val countFromSwift = StoreProbe.nativeRoundTrip(adapter)

        // Swift's loadAll() decoded Kotlin's loadAllWire() bytes: added 2, removed 1 -> 1.
        assertEquals(1, countFromSwift)

        // Swift's addWire/removeWire arg marshaling landed on the Kotlin impl.
        assertEquals(1, impl.items.size)
        assertEquals(2, impl.items[0].id)
        assertEquals("from-swift-2", impl.items[0].title)
        assertEquals(true, impl.items[0].done)
    }
}
