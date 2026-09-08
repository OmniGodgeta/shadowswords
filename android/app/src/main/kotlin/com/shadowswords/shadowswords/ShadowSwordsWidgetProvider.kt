package com.shadowswords.shadowswords

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.support.v4.media.session.PlaybackStateCompat
import android.view.View
import android.widget.RemoteViews
import androidx.media.session.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ShadowSwordsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val active = widgetData.getBoolean("music_active", false)
        val playing = widgetData.getBoolean("music_playing", false)
        val title = widgetData.getString("music_title", "") ?: ""
        val artist = widgetData.getString("music_artist", "") ?: ""

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.shadowswords_widget).apply {
                launch(context, R.id.w_play, "shadowswords://play")
                launch(context, R.id.w_random, "shadowswords://play/random")
                launch(context, R.id.w_movies, "shadowswords://movies")

                if (active) {
                    setViewVisibility(R.id.w_music_row, View.VISIBLE)
                    val label = if (artist.isNotBlank()) "♪ $title — $artist" else "♪ $title"
                    setTextViewText(R.id.w_music_text, label)
                    setImageViewResource(
                        R.id.w_toggle,
                        if (playing) android.R.drawable.ic_media_pause
                        else android.R.drawable.ic_media_play,
                    )
                    media(context, R.id.w_prev, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
                    media(context, R.id.w_toggle, PlaybackStateCompat.ACTION_PLAY_PAUSE)
                    media(context, R.id.w_next, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)
                } else {
                    setViewVisibility(R.id.w_music_row, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun RemoteViews.launch(context: Context, viewId: Int, uri: String) {
        setOnClickPendingIntent(
            viewId,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse(uri),
            ),
        )
    }

    private fun RemoteViews.media(context: Context, viewId: Int, action: Long) {
        setOnClickPendingIntent(
            viewId,
            MediaButtonReceiver.buildMediaButtonPendingIntent(context, action),
        )
    }
}
