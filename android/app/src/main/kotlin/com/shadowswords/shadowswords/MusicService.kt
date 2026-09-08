package com.shadowswords.shadowswords

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import org.json.JSONObject
import java.net.URL
import kotlin.concurrent.thread

/**
 * A MediaSession that mirrors the web music player's state so the lock screen,
 * Bluetooth, and car head-units get real metadata + transport controls.
 * Transport events are forwarded to [transportSink] (wired to Dart by
 * MainActivity), which calls window.SSMusic.* in the WebView.
 */
class MusicService : Service() {

    companion object {
        /** Set by MainActivity; receives "play" | "pause" | "next" | "prev" | "stop" | "seek:<sec>". */
        var transportSink: ((String) -> Unit)? = null

        const val ACTION_UPDATE = "com.shadowswords.shadowswords.MUSIC_UPDATE"
        const val ACTION_STOP = "com.shadowswords.shadowswords.MUSIC_STOP"
        const val EXTRA_STATE = "state"
        private const val CHANNEL = "ssw_music"
        private const val NOTIF_ID = 42
    }

    private lateinit var session: MediaSessionCompat
    private var art: Bitmap? = null
    private var artUrl: String? = null
    private var lastPlaying = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        session = MediaSessionCompat(this, "ShadowSwords").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = transportSink?.invoke("play") ?: Unit
                override fun onPause() = transportSink?.invoke("pause") ?: Unit
                override fun onSkipToNext() = transportSink?.invoke("next") ?: Unit
                override fun onSkipToPrevious() = transportSink?.invoke("prev") ?: Unit
                override fun onStop() {
                    transportSink?.invoke("stop")
                    stopSelf()
                }
                override fun onSeekTo(pos: Long) =
                    transportSink?.invoke("seek:${pos / 1000}") ?: Unit
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> apply(intent.getStringExtra(EXTRA_STATE))
        }
        return START_NOT_STICKY
    }

    private fun apply(json: String?) {
        val s = try { JSONObject(json ?: "{}") } catch (e: Exception) { JSONObject() }
        if (!s.optBoolean("active", false)) {
            stopSelf()
            return
        }
        val title = s.optString("title").ifBlank { "ShadowSwords" }
        val artist = s.optString("artist")
        val album = s.optString("album")
        val playing = s.optBoolean("playing", false)
        val duration = (s.optDouble("duration", 0.0) * 1000).toLong()
        val position = (s.optDouble("position", 0.0) * 1000).toLong()
        val newArtUrl = s.optString("artworkUrl").ifBlank { null }

        if (newArtUrl != artUrl) {
            artUrl = newArtUrl
            art = null
            if (newArtUrl != null) loadArt(newArtUrl)
        }

        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .apply { art?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
                .build()
        )
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_STOP or
                        PlaybackStateCompat.ACTION_SEEK_TO
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    position, 1f
                )
                .build()
        )
        lastPlaying = playing
        pushNotification(playing)
    }

    private fun loadArt(url: String) = thread(isDaemon = true) {
        try {
            val bmp = URL(url).openStream().use { BitmapFactory.decodeStream(it) }
            if (bmp != null && url == artUrl) {
                art = bmp
                android.os.Handler(mainLooper).post {
                    // re-emit metadata + notification with the art
                    session.controller?.metadata?.let { m ->
                        session.setMetadata(
                            MediaMetadataCompat.Builder(m)
                                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp)
                                .build()
                        )
                    }
                    pushNotification(lastPlaying)
                }
            }
        } catch (e: Exception) { /* no art, no problem */ }
    }

    private fun pushNotification(playing: Boolean) {
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
        val md = session.controller.metadata
        val openApp = PendingIntent.getActivity(
            this, 0, packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notif: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(md?.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: "ShadowSwords")
            .setContentText(md?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST))
            .setLargeIcon(art)
            .setContentIntent(openApp)
            .setDeleteIntent(
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_STOP
                )
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(
                android.R.drawable.ic_media_previous, "Previous",
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                )
            )
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play",
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_PLAY_PAUSE
                )
            )
            .addAction(
                android.R.drawable.ic_media_next, "Next",
                MediaButtonReceiver.buildMediaButtonPendingIntent(
                    this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                )
            )
            .setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .setOngoing(playing)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    override fun onDestroy() {
        session.isActive = false
        session.release()
        super.onDestroy()
    }
}
