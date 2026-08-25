package com.plantcompanion.plant_companion

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalTime

/**
 * VANYA's watering widget — an illustrated "spirit garden" scene rather
 * than plain text. The tree's condition reflects actual garden health
 * (thriving / attention / overdue / no plants yet — see garden_health
 * below), lighting reflects real day vs night, and a live clock overlays
 * on top via a plain TextClock in the layout — that refreshes itself
 * every minute on its own, system-driven, so there's no
 * BroadcastReceiver or battery cost involved in "live time" here.
 *
 * `widgetData` is populated from the Flutter side via
 * lib/services/widget_service.dart's `HomeWidget.saveWidgetData` calls.
 * garden_health is written there as one of "thriving" | "attention" |
 * "overdue" | "empty" — this file only ever has to cross that against
 * day/night, never compute watering thresholds itself (those live in one
 * place, Plant.nextWateringDue on the Dart side).
 */
class WateringWidgetProvider : HomeWidgetProvider() {

  companion object {
    // 6am-7pm reads as "day" — a plain, no-API heuristic (no
    // location/sunrise-sunset lookup), the same idea as the app's own
    // _greeting() time-of-day buckets in home_screen.dart. Re-evaluated
    // every time this runs (the periodic 30-min update, or an explicit
    // push from the app), which is plenty granular for a mood/lighting
    // change like this — nobody needs it to the exact minute.
    private const val DAY_START_HOUR = 6
    private const val DAY_END_HOUR = 19
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val plantName = widgetData.getString("plant_name", null) ?: "VANYA"
    val status = widgetData.getString("plant_status", null) ?: "Open the app to see your plants"
    val health = widgetData.getString("garden_health", null) ?: "empty"

    val hour = LocalTime.now().hour
    val isDay = hour in DAY_START_HOUR until DAY_END_HOUR
    val sceneRes = sceneDrawableFor(health, isDay)

    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.watering_widget).apply {
            setImageViewResource(R.id.widget_scene, sceneRes)
            setTextViewText(R.id.widget_plant_name, plantName)
            setTextViewText(R.id.widget_status, status)
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
          }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  /**
   * Explicit branches (not a getIdentifier() string lookup) so every
   * drawable is referenced directly — keeps R8's resource shrinker from
   * ever being able to strip one of the 8 scenes as "unused", and reads
   * as a plain, exhaustive table rather than reconstructed resource names.
   * Falls back to the "empty" scene for any unrecognized health value —
   * shouldn't happen (Flutter only ever writes one of the four), but a
   * resource lookup miss must never crash the widget.
   */
  private fun sceneDrawableFor(health: String, isDay: Boolean): Int {
    return when (health) {
      "thriving" -> if (isDay) R.drawable.widget_thriving_day else R.drawable.widget_thriving_night
      "attention" -> if (isDay) R.drawable.widget_attention_day else R.drawable.widget_attention_night
      "overdue" -> if (isDay) R.drawable.widget_overdue_day else R.drawable.widget_overdue_night
      else -> if (isDay) R.drawable.widget_empty_day else R.drawable.widget_empty_night
    }
  }
}
