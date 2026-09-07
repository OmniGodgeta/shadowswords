package com.shadowswords.shadowswords

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * A bare foreground service kept alive while the web music player is playing, so
 * the OS doesn't reap the process in the background. The actual lock-screen
 * artwork and transport controls come from the WebView's own MediaSession
 * (the page drives navigator.mediaSession).
 */
class MusicService : Service() {

    companion object {
        const val ACTION_STOP = "com.shadowswords.shadowswords.STOP_MUSIC"
        private const val CHANNEL = "ssw_music"
        private const val NOTIF_ID = 42
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL, "Music playback", NotificationManager.IMPORTANCE_LOW
                    ).apply { setShowBadge(false) }
                )
            }
        }

        val openApp = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, MusicService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val notif: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("ShadowSwords")
            .setContentText("Music playing")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(openApp)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stop)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, notif)
        }
        // If the OS kills us, don't resurrect — the app re-starts us when audio resumes.
        return START_NOT_STICKY
    }
}
