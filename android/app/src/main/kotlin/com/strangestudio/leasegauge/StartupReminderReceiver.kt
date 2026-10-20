package com.strangestudio.leasegauge

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class StartupReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)) return

        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(enabledKey, false)) return

        val now = System.currentTimeMillis()
        val lastShownAt = preferences.getLong(lastShownAtKey, 0L)
        if (now - lastShownAt < minimumIntervalMillis) return
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val manager = NotificationManagerCompat.from(context)
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    context.getString(R.string.startup_reminder_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = context.getString(R.string.startup_reminder_channel_description)
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.startup_reminder_title))
            .setContentText(context.getString(R.string.startup_reminder_body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(notificationId, notification)
        preferences.edit().putLong(lastShownAtKey, now).apply()
    }

    companion object {
        const val preferencesName = "leasegauge_settings"
        const val enabledKey = "startup_reminder_enabled"
        private const val lastShownAtKey = "startup_reminder_last_shown_at"
        private const val channelId = "before_drive_reminders"
        private const val notificationId = 4102
        private const val minimumIntervalMillis = 24L * 60L * 60L * 1000L
    }
}
