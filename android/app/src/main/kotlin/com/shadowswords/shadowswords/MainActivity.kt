package com.shadowswords.shadowswords

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

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
                else -> result.notImplemented()
            }
        }
        // Forward MediaSession transport events from the service to Dart.
        MusicService.transportSink = { event ->
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod("transport", event)
            }
        }
    }

    override fun onDestroy() {
        MusicService.transportSink = null
        channel = null
        super.onDestroy()
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
}
