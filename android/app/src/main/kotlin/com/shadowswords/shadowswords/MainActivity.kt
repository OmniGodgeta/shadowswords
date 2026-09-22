package com.shadowswords.shadowswords

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.PixelCopy
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    // --- native netplay-invite notifications ---------------------------------
    // The WebView is throttled while the app is backgrounded, so it can miss
    // invites. While backgrounded (Dart tells us via start/stopInviteWatch) we
    // poll /play/invites here and post a notification that deep-links back in.
    private val inviteHandler = Handler(Looper.getMainLooper())
    private var inviteRunnable: Runnable? = null
    private var lastInviteId: String? = null
    private val INVITE_CHANNEL = "retroverse_invites"
    // Two independent call sites can both invoke "requestMic" close together:
    // the WebView's own onPlatformPermissionRequest (fired by getUserMedia)
    // and a fire-and-forget SSNotify{mic:true} ping the site sends to nudge
    // the OS dialog open early. A single pendingMicResult slot meant the
    // second call clobbered the first with success(false) *before the user
    // had answered anything* — the dialog the user actually saw and allowed
    // belonged to whichever call registered last, while the earlier call
    // (often the one whose result actually decided request.grant/deny) had
    // already been resolved false. That's the "I allow every time and it
    // still says denied" bug. Fix: queue every pending result and resolve
    // them all with the real answer once the user actually responds, instead
    // of only the most recently stored one.
    private val pendingMicResults = mutableListOf<MethodChannel.Result>()
    private val MIC_REQ = 4711
    private val ACTION_PACKAGE_INSTALL_STATUS = "com.shadowswords.shadowswords.PACKAGE_INSTALL_STATUS"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "shadowswords/native"
        )
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "screenshot" -> takeScreenshot(result)
                "updateMusic" -> {
                    val i = Intent(this, MusicService::class.java).apply {
                        action = MusicService.ACTION_UPDATE
                        putExtra(MusicService.EXTRA_STATE, call.arguments as? String)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        startForegroundService(i) else startService(i)
                    result.success(true)
                }
                "stopMusic" -> {
                    startService(
                        Intent(this, MusicService::class.java)
                            .setAction(MusicService.ACTION_STOP)
                    )
                    result.success(true)
                }
                "partyStart" -> {
                    val m = call.arguments as? Map<*, *>
                    val muted = m?.get("muted") as? Boolean ?: false
                    val i = Intent(this, PartyService::class.java).apply {
                        action = PartyService.ACTION_START
                        putExtra(PartyService.EXTRA_MUTED, muted)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            startForegroundService(i) else startService(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "partyStop" -> {
                    startService(
                        Intent(this, PartyService::class.java)
                            .setAction(PartyService.ACTION_STOP)
                    )
                    result.success(true)
                }
                "partyMute" -> {
                    val muted = (call.arguments as? Boolean) ?: true
                    startService(
                        Intent(this, PartyService::class.java)
                            .setAction(PartyService.ACTION_MUTE)
                            .putExtra(PartyService.EXTRA_MUTED, muted)
                    )
                    result.success(true)
                }
                "canOverlay" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
                )
                "backgroundApp" -> {
                    // Used while a party call is live so back doesn't kill the call.
                    moveTaskToBack(true)
                    result.success(true)
                }
                "requestOverlay" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Exception) { /* */ }
                    }
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrBlank()) {
                        result.error("bad", "missing path", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(path))
                }
                "startInviteWatch" -> {
                    val m = call.arguments as? Map<*, *>
                    val cid = m?.get("cid") as? String
                    val origin = m?.get("origin") as? String
                    if (cid.isNullOrBlank() || origin.isNullOrBlank()) result.success(false)
                    else { startInviteWatch(cid, origin); result.success(true) }
                }
                "stopInviteWatch" -> { stopInviteWatch(); result.success(true) }
                "requestMic" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        val alreadyPending = pendingMicResults.isNotEmpty()
                        pendingMicResults.add(result)
                        // A dialog is already up for an earlier caller — queue behind
                        // it instead of firing requestPermissions again (that's what
                        // used to clobber the earlier call's result with false).
                        if (!alreadyPending) requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQ)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Forward MediaSession transport events from the service to Dart.
        MusicService.transportSink = { event ->
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod("transport", event)
            }
        }
        // Notification / floating-bubble controls for the party call.
        PartyService.actionSink = { action ->
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod("partyAction", action)
            }
        }
        // Tapping an invite notification when the app was killed delivers the
        // join URL as the launch intent, not through onNewIntent. Forward it
        // once the channel exists so cold starts can join too.
        intent?.getStringExtra("joinUrl")?.let { url ->
            intent.removeExtra("joinUrl")
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod("openInvite", url)
            }
        }
    }

    override fun onDestroy() {
        MusicService.transportSink = null
        PartyService.actionSink = null
        stopService(Intent(this, MusicService::class.java))
        stopInviteWatch()
        channel = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("joinUrl")?.let { url ->
            Handler(Looper.getMainLooper()).post { channel?.invokeMethod("openInvite", url) }
        }
        if (intent.action == ACTION_PACKAGE_INSTALL_STATUS) {
            // PackageInstaller.Session.commit() result. The install itself either
            // succeeds silently (app just updates) or the system shows its own
            // confirmation/error UI — nothing for us to display here, but Dart's
            // resume-and-recheck flow (see app updater handoff notes below)
            // already re-verifies the installed version on app resume regardless.
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_REQ) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingMicResults.forEach { it.success(granted) }
            pendingMicResults.clear()
        }
    }

    private fun startInviteWatch(cid: String, origin: String) {
        stopInviteWatch()
        val base = origin.trimEnd('/')
        val r = object : Runnable {
            override fun run() {
                Thread {
                    try {
                        val u = URL("$base/play/invites?cid=" + URLEncoder.encode(cid, "UTF-8"))
                        val c = (u.openConnection() as HttpURLConnection).apply {
                            connectTimeout = 8000; readTimeout = 8000; requestMethod = "GET"
                        }
                        val body = c.inputStream.bufferedReader().use { it.readText() }
                        val arr = JSONObject(body).optJSONArray("invites")
                        if (arr != null && arr.length() > 0) {
                            val inv = arr.getJSONObject(0)
                            val id = inv.optString("id")
                            if (id.isNotEmpty() && id != lastInviteId) {
                                lastInviteId = id
                                val from = inv.optString("fromName", "Someone")
                                val game = inv.optString("name", "a game")
                                val room = inv.optString("room")
                                val sys = inv.optString("sys")
                                val file = inv.optString("file")
                                // Encode each segment: ROM names contain spaces,
                                // brackets and sometimes sub-directories.
                                val enc = { s: String -> URLEncoder.encode(s, "UTF-8").replace("+", "%20") }
                                val filePath = file.split("/").joinToString("/") { enc(it) }
                                val join = if (room.isNotEmpty())
                                    "$base/?join=" + enc(room) + "#/play/" + enc(sys) + "/" + filePath
                                else "$base/"
                                inviteHandler.post { postInviteNotification(from, game, join) }
                            }
                        }
                    } catch (_: Exception) { /* offline or no invites */ }
                }.start()
                inviteHandler.postDelayed(this, 25000)
            }
        }
        inviteRunnable = r
        inviteHandler.postDelayed(r, 1500)
    }

    private fun stopInviteWatch() {
        inviteRunnable?.let { inviteHandler.removeCallbacks(it) }
        inviteRunnable = null
    }

    private fun postInviteNotification(from: String, game: String, joinUrl: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                nm.getNotificationChannel(INVITE_CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(INVITE_CHANNEL, "Netplay invites", NotificationManager.IMPORTANCE_HIGH)
                )
            }
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("joinUrl", joinUrl)
            }
            val pi = PendingIntent.getActivity(this, joinUrl.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(this, INVITE_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("$from invited you")
                .setContentText("Tap to play $game together")
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .build()
            nm.notify(joinUrl.hashCode(), n)
        } catch (_: Exception) { /* notifications not permitted */ }
    }

    private fun takeScreenshot(result: MethodChannel.Result) {
        val window = window ?: run { result.success(null); return }
        val view = window.decorView
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PixelCopy.request(window, bitmap, { copyResult ->
                if (copyResult == PixelCopy.SUCCESS) result.success(save(bitmap))
                else result.success(null)
            }, Handler(Looper.getMainLooper()))
        } else {
            @Suppress("DEPRECATION")
            view.draw(android.graphics.Canvas(bitmap))
            result.success(save(bitmap))
        }
    }

    private fun save(bitmap: Bitmap): String? {
        val name = "RetroVerse_" +
            SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".png"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/RetroVerse"
                )
            }
        }
        return try {
            val uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values
            ) ?: return null
            contentResolver.openOutputStream(uri)?.use { out: OutputStream ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            uri.toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "needPermission"
        }

        // --- Robust PackageInstaller Session Approach ---
        return try {
            val packageInstaller = packageManager.packageInstaller
            val params = android.content.pm.PackageInstaller.SessionParams(
                android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            session.openWrite("package", 0, file.length()).use { outputStream ->
                file.inputStream().use { inputStream -> inputStream.copyTo(outputStream) }
                session.fsync(outputStream)
            }

            val statusIntent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_PACKAGE_INSTALL_STATUS
            }
            val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            val pendingIntent = PendingIntent.getActivity(this, sessionId, statusIntent, pendingIntentFlags)
            session.commit(pendingIntent.intentSender)
            session.close()
            "ok"
        } catch (e: Exception) {
            // Fallback to the traditional method if Session fails
            try {
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri("", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                "fallback_ok"
            } catch (fallbackEx: Exception) {
                "installer: ${fallbackEx.javaClass.simpleName}"
            }
        }
    }
}
