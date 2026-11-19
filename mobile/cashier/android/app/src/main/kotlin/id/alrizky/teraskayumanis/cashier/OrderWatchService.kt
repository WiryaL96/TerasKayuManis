package id.alrizky.teraskayumanis.cashier

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.*
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.random.Random

/** Read-only notification lease. No Supabase session/refresh token enters native code. */
class OrderWatchService : Service() {
    companion object {
        private const val CHANNEL_WATCH = "tkm_cashier_watch"
        private const val CHANNEL_ORDERS = "tkm_new_orders"
        private const val WATCH_ID = 101
        private const val ORDER_ID = 102
        private const val INTERVAL = 5000L
        private var active: OrderWatchService? = null
        private val revoker = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(8), ThreadPoolExecutor.DiscardOldestPolicy())
        private val deadlines = Executors.newSingleThreadScheduledExecutor()

        fun start(context: Context, state: JSONObject) {
            WatchVault.validate(state)
            val epoch = WatchVault.replace(context, state)
            val intent = Intent(context, OrderWatchService::class.java).putExtra("epoch", epoch)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context, clear: Boolean): Map<String, Any?> {
            val state = WatchVault.read(context)
            // Invalidate disk writes before cancellation; a late HTTP response
            // can no longer restore a token or post a notification.
            try { WatchVault.clear(context) } finally {
                active?.finish()
                context.stopService(Intent(context, OrderWatchService::class.java))
            }
            if (clear) (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(ORDER_ID)
            if (state != null) revoker.execute {
                try { request(state, "DELETE") } catch (_: Exception) { /* Lease has a bounded TTL. */ }
            }
            return mapOf(
                "scope" to state?.optString("scope"),
                "seen" to state?.optJSONArray("seen")?.let { array -> List(array.length()) { array.getString(it) } },
                "revision" to state?.optString("revision"),
            )
        }

        private fun request(state: JSONObject, method: String, register: (HttpURLConnection?) -> Unit = {}): JSONObject {
            val connection = URL(state.getString("apiBase") + "admin/watch").openConnection() as HttpURLConnection
            register(connection)
            // readTimeout applies to each read. A trickling response must not
            // occupy the sole worker forever or outlive its bounded wake lock.
            val deadline = deadlines.schedule({ connection.disconnect() }, 16, TimeUnit.SECONDS)
            val expiresAt = SystemClock.elapsedRealtime() + 16000
            try {
                connection.requestMethod = method
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.setRequestProperty("Accept", "application/json")
                connection.setRequestProperty("X-Watch-Token", state.getString("token"))
                val status = connection.responseCode
                if (status !in 200..299) {
                    val seconds = connection.getHeaderField("Retry-After")?.toLongOrNull()
                    throw WatchHttpError(status, (seconds ?: 60).coerceIn(1, 3600) * 1000)
                }
                if (status == 204) return JSONObject()
                val bytes = ByteArrayOutputStream()
                connection.inputStream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        if (SystemClock.elapsedRealtime() >= expiresAt) throw java.net.SocketTimeoutException("Watch deadline")
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (bytes.size() + count > 128 * 1024) throw IllegalStateException("Response too large")
                        bytes.write(buffer, 0, count)
                    }
                }
                return JSONObject(bytes.toString("UTF-8"))
            } finally {
                deadline.cancel(false)
                register(null)
                connection.disconnect()
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var worker = Executors.newSingleThreadExecutor()
    @Volatile private var stopped = false
    @Volatile private var connection: HttpURLConnection? = null
    private var epoch = 0L
    private var state: JSONObject? = null
    private var failures = 0
    private val policy = WatchPolicy()
    private var soundPool: SoundPool? = null
    private var sample = 0
    private var lastChimeAt = 0L
    private val poller = Runnable { poll() }

    override fun onCreate() {
        super.onCreate()
        active = this
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(poller)
        stopped = false
        if (worker.isShutdown) worker = Executors.newSingleThreadExecutor()
        epoch = WatchVault.epoch()
        state = WatchVault.read(this)
        if (state == null || !valid()) { finish(); return START_NOT_STICKY }
        policy.start()
        startForeground(WATCH_ID, notification(CHANNEL_WATCH, "Pemantau pesanan aktif", "Berlaku selama izin perangkat dan sesi pemantauan aktif.", true))
        if (state!!.optBoolean("sound", true)) loadChime()
        // Repeated starts invalidate the old generation; at most one request can
        // run on the worker. New polling begins after its completion callback.
        handler.post(poller)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onTimeout(startId: Int, fgsType: Int) { try { stop(this, false) } finally { finish() } }
    override fun onDestroy() { finish(); super.onDestroy() }

    private fun valid(): Boolean = !stopped && epoch == WatchVault.epoch() &&
        (state?.optLong("expiresAt") ?: 0) > System.currentTimeMillis()

    private fun poll() {
        if (!valid()) { finish(); return }
        val ticket = policy.acquire() ?: return
        val generation = epoch
        val snapshot = JSONObject(state.toString())
        worker.execute {
            var response: JSONObject? = null
            var error: Exception? = null
            var lock: PowerManager.WakeLock? = null
            try {
                lock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tkm:orderwatch")
                    .apply { setReferenceCounted(false); acquire(20000) }
                response = request(snapshot, "GET") { connection = it }
            } catch (failure: Exception) { error = failure }
            finally { try { if (lock?.isHeld == true) lock.release() } catch (_: Exception) {} }
            handler.post {
                val current = policy.complete(ticket)
                if (!current || generation != epoch || !valid()) {
                    if (!valid()) finish() else handler.post(poller)
                    return@post
                }
                val failure = error
                if (failure is WatchHttpError && failure.status in listOf(401, 403, 404, 410)) {
                    stop(this, false); return@post
                }
                var delay = INTERVAL
                try {
                    if (failure != null) throw failure
                    val data = response!!
                    val ids = data.getJSONArray("new_orders")
                    if (ids.length() > 1000) throw IllegalStateException("Invalid sync response")
                    val previous = snapshot.optJSONArray("seen")
                    val seen = previous?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() }
                    val fresh = (0 until ids.length()).count { seen != null && ids.getString(it) !in seen }
                    val revision = data.getString("revision")
                    val changed = revision != snapshot.optString("revision") || previous?.toString() != ids.toString()
                    snapshot.put("seen", ids).put("revision", revision)
                    if (changed && !WatchVault.save(this, generation, snapshot)) return@post
                    state = snapshot
                    failures = 0
                    if (fresh > 0) announce(fresh)
                } catch (failure: Exception) {
                    failures = min(failures + 1, 6)
                    delay = if (failure is WatchHttpError && failure.status == 429) failure.retryMs
                        else min(60000L, INTERVAL * (1L shl failures)) + Random.nextLong(1000)
                }
                if (valid()) handler.postDelayed(poller, delay)
            }
        }
    }

    private fun finish() {
        if (stopped) return
        stopped = true
        policy.stop()
        handler.removeCallbacksAndMessages(null)
        connection?.disconnect()
        connection = null
        worker.shutdownNow()
        soundPool?.release()
        soundPool = null
        state = null
        if (active === this) active = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_WATCH, "Pemantau pesanan", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null); setShowBadge(false) })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ORDERS, "Pesanan baru", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(true) })
    }

    private fun notification(channel: String, title: String, text: String, ongoing: Boolean): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)!!.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
        return builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setContentText(text)
            .setContentIntent(pending).setOngoing(ongoing).setAutoCancel(!ongoing).setOnlyAlertOnce(true).build()
    }

    private fun announce(count: Int) {
        if (!valid()) return
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (!manager.areNotificationsEnabled()) return
            if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ORDERS)?.importance == NotificationManager.IMPORTANCE_NONE) return
            manager.notify(ORDER_ID,
                notification(CHANNEL_ORDERS, "$count pesanan baru masuk", "Buka aplikasi untuk memeriksa antrean.", false))
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (state?.optBoolean("sound", true) == true && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
                manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL &&
                SystemClock.elapsedRealtime() - lastChimeAt > 2000) {
                soundPool?.play(sample, 1f, 1f, 1, 0, 1f)
                lastChimeAt = SystemClock.elapsedRealtime()
            }
        } catch (_: SecurityException) { /* Permission may be revoked while hidden. */ }
    }

    private fun loadChime() {
        if (soundPool != null) return
        val pool = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool.setOnLoadCompleteListener { _, id, status -> if (status == 0) sample = id }
        try {
            assets.openFd("flutter_assets/assets/sound/chaching_notif.mp3").use { pool.load(it.fileDescriptor, it.startOffset, it.length, 1) }
            soundPool = pool
        } catch (_: Exception) { pool.release() }
    }
}

private class WatchHttpError(val status: Int, val retryMs: Long) : Exception()
