package com.strangestudio.leasegauge

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.strangestudio.leasegauge/startup_reminder"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(isAutomotive())
                    "isEnabled" -> result.success(
                        getSharedPreferences(
                            StartupReminderReceiver.preferencesName,
                            MODE_PRIVATE,
                        ).getBoolean(StartupReminderReceiver.enabledKey, false),
                    )
                    "setEnabled" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        getSharedPreferences(
                            StartupReminderReceiver.preferencesName,
                            MODE_PRIVATE,
                        ).edit().putBoolean(
                            StartupReminderReceiver.enabledKey,
                            enabled,
                        ).apply()
                        if (
                            enabled &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                notificationPermissionRequest,
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAutomotive(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)

    private companion object {
        const val notificationPermissionRequest = 4102
    }
}
