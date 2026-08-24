package com.plantcompanion.plant_companion

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * VANYA's watering widget — v1, deliberately simple: shows just the single
 * most-urgent-to-water plant (nickname + due status), tap opens the app.
 * No in-place actions (e.g. "mark watered" from the widget) yet.
 *
 * `widgetData` here is populated from the Flutter side via
 * lib/services/widget_service.dart's `HomeWidget.saveWidgetData` calls —
 * this class only ever reads three string keys it writes: plant_name,
 * plant_status, plant_urgency ("due" | "ok" | "neutral" — decides the
 * status line's color, matching the accent-vs-secondary convention used
 * everywhere else in the app for "needs attention" vs "on track").
 */
class WateringWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val plantName = widgetData.getString("plant_name", null) ?: "VANYA"
    val status = widgetData.getString("plant_status", null) ?: "Open the app to see your plants"
    val urgency = widgetData.getString("plant_urgency", null) ?: "neutral"

    val statusColor =
        if (urgency == "due") {
          ContextCompat.getColor(context, R.color.widget_accent)
        } else {
          ContextCompat.getColor(context, R.color.widget_text_secondary)
        }

    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.watering_widget).apply {
            setTextViewText(R.id.widget_plant_name, plantName)
            setTextViewText(R.id.widget_status, status)
            setTextColor(R.id.widget_status, statusColor)
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
          }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
