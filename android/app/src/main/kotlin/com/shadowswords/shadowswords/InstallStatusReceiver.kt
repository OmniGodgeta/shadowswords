package com.shadowswords.shadowswords

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * Receives PackageInstaller.Session.commit() results.
 *
 * The result used to go to MainActivity through PendingIntent.getActivity(),
 * but Android 14+ blocks that as a background activity launch (the system is
 * the sender), so STATUS_PENDING_USER_ACTION never arrived and the update sat
 * on "Opening installer…" forever. A broadcast is always delivered; from here
 * the app (still in the foreground) opens the system confirmation itself.
 */
class InstallStatusReceiver : BroadcastReceiver() {
    companion object {
        /** MainActivity forwards failures to Dart through this. */
        var statusSink: ((String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm == null) {
                    statusSink?.invoke("installer: no confirmation intent")
                    return
                }
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            PackageInstaller.STATUS_SUCCESS -> Unit // the process is replaced by the update
            else -> {
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                // STATUS_FAILURE_ABORTED = the user cancelled; not worth an error.
                if (status != PackageInstaller.STATUS_FAILURE_ABORTED) {
                    statusSink?.invoke("installer: ${msg ?: "status $status"}")
                }
            }
        }
    }
}
