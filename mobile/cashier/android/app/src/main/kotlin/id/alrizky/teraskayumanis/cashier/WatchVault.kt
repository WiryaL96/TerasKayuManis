package id.alrizky.teraskayumanis.cashier

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** A single encrypted record and generation fence. Never persists Supabase tokens. */
object WatchVault {
    private const val PREFS = "tkm_watch_v2"
    private const val ALIAS = "tkm.watch.lease.v2"
    private var generation = 0L
    @Synchronized fun epoch() = generation
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun validate(state: JSONObject) {
        val endpoint = URI(state.getString("apiBase"))
        require(endpoint.scheme == "https" && !endpoint.host.isNullOrBlank() && endpoint.userInfo == null && endpoint.query == null && endpoint.fragment == null && endpoint.path.endsWith("/api/core/"))
        require(state.getString("token").matches(Regex("^[a-f0-9]{64}$")))
        require(state.getString("scope").length in 1..2048)
        val remaining = state.getLong("expiresAt") - System.currentTimeMillis()
        require(remaining in 1..(6 * 60 * 60 * 1000L))
        require((state.optJSONArray("seen")?.length() ?: 0) <= 1000)
    }

    @Synchronized fun replace(context: Context, state: JSONObject): Long {
        validate(state)
        generation++
        // Erase the old plaintext watcher record on every upgrade/start.
        context.getSharedPreferences("tkm_order_watch", Context.MODE_PRIVATE).edit().clear().commit()
        check(write(context, state))
        return generation
    }

    @Synchronized fun save(context: Context, expected: Long, state: JSONObject): Boolean {
        if (expected != generation) return false
        return write(context, state)
    }

    @Synchronized fun clear(context: Context) {
        generation++
        check(prefs(context).edit().clear().commit())
        check(context.getSharedPreferences("tkm_order_watch", Context.MODE_PRIVATE).edit().clear().commit())
    }

    @Synchronized fun read(context: Context): JSONObject? = try {
        val encoded = prefs(context).getString("lease", null)
        if (encoded == null) null else {
            val parts = encoded.split(':', limit = 2)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
            JSONObject(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
        }
    } catch (_: Exception) { null }

    private fun write(context: Context, state: JSONObject): Boolean {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val encrypted = Base64.encodeToString(cipher.doFinal(state.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        return prefs(context).edit().putString("lease", "$iv:$encrypted").commit()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
}
