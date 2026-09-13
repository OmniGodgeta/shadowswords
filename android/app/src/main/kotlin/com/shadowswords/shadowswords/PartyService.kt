package com.shadowswords.shadowswords

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.core.app.NotificationCompat
import kotlin.math.abs

/**
 * Keeps a RetroVerse party call alive while the app is in the background and
 * shows a floating bubble over other apps.
 *
 * The WebRTC engine itself is the site running in the main WebView; this
 * service holds the process in the foreground (so Android does not freeze the
 * WebView and drop the call) and surfaces mute/leave controls. Swiping the app
 * away still tears the process down, ending the call — see FEATURE-BACKLOG.md
 * for the follow-up that moves the call engine into this service.
 */
class PartyService : Service() {

    companion object {
        /** Set by MainActivity; receives "mute" | "unmute" | "leave". */
        var actionSink: ((String) -> Unit)? = null

        const val ACTION_START = "com.shadowswords.shadowswords.PARTY_START"
        const val ACTION_STOP = "com.shadowswords.shadowswords.PARTY_STOP"
        const val ACTION_MUTE = "com.shadowswords.shadowswords.PARTY_MUTE"
        const val EXTRA_MUTED = "muted"
        private const val CHANNEL = "ssw_party"
        private const val NOTIF_ID = 43
    }

    private var bubble: TextView? = null
    private var lp: WindowManager.LayoutParams? = null
    private var wm: WindowManager? = null
    private var muted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                actionSink?.invoke("leave")
                removeBubble()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_MUTE -> {
                muted = intent.getBooleanExtra(EXTRA_MUTED, !muted)
                actionSink?.invoke(if (muted) "mute" else "unmute")
                updateNotification()
                updateBubble()
            }
            ACTION_START -> {
                muted = intent.getBooleanExtra(EXTRA_MUTED, false)
                startInForeground()
                showBubble()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Party call", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notif = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val mute = PendingIntent.getService(
            this, 1,
            Intent(this, PartyService::class.java).setAction(ACTION_MUTE).putExtra(EXTRA_MUTED, !muted),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val leave = PendingIntent.getService(
            this, 2, Intent(this, PartyService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("RetroVerse party")
            .setContentText(if (muted) "On a call · microphone muted" else "On a call · microphone live")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, if (muted) "Unmute" else "Mute", mute)
            .addAction(0, "Leave", leave)
            .build()
    }

    // ---- floating bubble (needs SYSTEM_ALERT_WINDOW) ----------------------
    private fun showBubble() {
        if (bubble != null) return
        if (!Settings.canDrawOverlays(this)) return
        val manager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = manager
        val density = resources.displayMetrics.density
        val size = (56 * density).toInt()
        val view = TextView(this).apply {
            text = if (muted) "🔇" else "🎙"
            textSize = 24f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#CC06060C"))
                setStroke((2 * density).toInt(), Color.parseColor("#FFD23D"))
            }
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        val params = WindowManager.LayoutParams(size, size, type, flags, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (24 * density).toInt()
            y = (resources.displayMetrics.heightPixels * 0.28).toInt()
        }
        lp = params
        view.setOnTouchListener(object : View.OnTouchListener {
            private var downX = 0f; private var downY = 0f
            private var startX = 0; private var startY = 0
            private var dragged = false
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = e.rawX; downY = e.rawY
                        startX = params.x; startY = params.y; dragged = false; return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (e.rawX - downX).toInt(); val dy = (e.rawY - downY).toInt()
                        if (abs(dx) > 12 || abs(dy) > 12) dragged = true
                        params.x = startX + dx; params.y = startY + dy
                        wm?.updateViewLayout(v, params); return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!dragged) openApp()
                        return true
                    }
                    else -> return false
                }
            }
        })
        view.setOnLongClickListener {
            muted = !muted
            actionSink?.invoke(if (muted) "mute" else "unmute")
            updateNotification(); updateBubble(); true
        }
        bubble = view
        try {
            manager.addView(view, params)
        } catch (e: Exception) {
            bubble = null
        }
    }

    private fun updateBubble() { bubble?.text = if (muted) "🔇" else "🎙" }

    private fun removeBubble() {
        bubble?.let { runCatching { wm?.removeView(it) } }
        bubble = null
        wm = null
        lp = null
    }

    private fun openApp() {
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
    }
}
