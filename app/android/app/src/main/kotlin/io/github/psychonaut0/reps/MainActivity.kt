package io.github.psychonaut0.reps

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reps/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstalls" -> {
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            packageManager.canRequestPackageInstalls() else true
                        result.success(ok)
                    }
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                startActivity(Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")))
                            } catch (e: Exception) {
                                // No "install unknown apps" Settings screen on this
                                // build — degrade gracefully rather than throwing
                                // a PlatformException across the channel.
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
