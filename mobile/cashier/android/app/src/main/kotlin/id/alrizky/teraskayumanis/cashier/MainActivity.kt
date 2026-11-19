package id.alrizky.teraskayumanis.cashier

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "id.alrizky.teraskayumanis.cashier/watch"
        const val NOTIFICATION_PERMISSION_REQUEST = 4311
    }

    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            val state = JSONObject(call.arguments as Map<*, *>)
                            OrderWatchService.start(applicationContext, state)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("watch_failed", "Pemantauan belum dapat dimulai.", null)
                        }
                    }
                    "stop" -> {
                        try {
                            val clear = call.argument<Boolean>("clear") ?: false
                            result.success(OrderWatchService.stop(applicationContext, clear))
                        } catch (error: Exception) {
                            result.error("stop_failed", "Pemantauan belum dapat dihentikan.", null)
                        }
                    }
                    "ensureNotificationPermission" -> requestNotificationPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.success(false)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        result.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }
}
