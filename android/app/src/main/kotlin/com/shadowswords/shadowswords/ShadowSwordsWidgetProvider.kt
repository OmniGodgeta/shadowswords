package com.shadowswords.shadowswords

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ShadowSwordsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.shadowswords_widget).apply {
                bind(context, R.id.w_play, "shadowswords://play")
                bind(context, R.id.w_random, "shadowswords://play/random")
                bind(context, R.id.w_movies, "shadowswords://movies")
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun RemoteViews.bind(context: Context, viewId: Int, uri: String) {
        setOnClickPendingIntent(
            viewId,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse(uri),
            ),
        )
    }
}
