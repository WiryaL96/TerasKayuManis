package id.alrizky.teraskayumanis.cashier
import org.junit.Assert.*
import org.junit.Test

class WatchPolicyTest {
    @Test fun slowRequestCannotAccumulateWork() {
        val state = WatchPolicy()
        state.start()
        val first = state.acquire()!!
        repeat(20) { assertNull(state.acquire()) }
        assertTrue(state.complete(first))
        assertNotNull(state.acquire())
    }
    @Test fun logoutRejectsLateResults() {
        val state = WatchPolicy()
        state.start()
        val first = state.acquire()!!
        state.stop()
        assertFalse(state.complete(first))
        assertNull(state.acquire())
    }
    @Test fun restartRejectsPreviousGeneration() {
        val state = WatchPolicy()
        state.start()
        val first = state.acquire()!!
        state.start()
        assertNull(state.acquire())
        assertFalse(state.complete(first))
        val second = state.acquire()!!
        assertTrue(state.current(second))
        assertFalse(state.current(first))
    }
}
