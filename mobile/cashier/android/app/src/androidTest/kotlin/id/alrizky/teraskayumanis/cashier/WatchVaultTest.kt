package id.alrizky.teraskayumanis.cashier
import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WatchVaultTest {
    @Test fun encryptedLeaseAndLogoutFence() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val token = "a".repeat(64)
        val state = JSONObject().put("apiBase", "https://example.test/api/core/")
            .put("token", token).put("scope", "fixture").put("expiresAt", System.currentTimeMillis() + 60000)
        try {
            context.getSharedPreferences("tkm_order_watch", Context.MODE_PRIVATE).edit().putString("refresh", "old-fixture").commit()
            val epoch = WatchVault.replace(context, state)
            val stored = context.getSharedPreferences("tkm_watch_v2", Context.MODE_PRIVATE).getString("lease", "")!!
            assertFalse(stored.contains(token))
            assertEquals(token, WatchVault.read(context)!!.getString("token"))
            assertTrue(context.getSharedPreferences("tkm_order_watch", Context.MODE_PRIVATE).all.isEmpty())
            WatchVault.clear(context)
            assertFalse(WatchVault.save(context, epoch, state))
            assertNull(WatchVault.read(context))
        } finally { WatchVault.clear(context) }
    }
}
