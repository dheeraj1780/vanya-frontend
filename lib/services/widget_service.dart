import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/models.dart';

/// Keeps the Android home-screen "Watering" widget in sync with the app's
/// own plant data. Deliberately simple (v1): shows just the single most
/// urgent plant to water — nickname + due status — not a full list, and
/// tapping it just opens the app rather than doing anything in place (e.g.
/// a "mark watered" action right on the widget). See
/// android/app/src/main/kotlin/.../WateringWidgetProvider.kt for the
/// native side that actually renders this.
///
/// home_widget's saveWidgetData just writes into the widget's own
/// SharedPreferences-backed store; updateWidget() is what tells Android to
/// actually redraw with that new data. Android also refreshes it on its
/// own periodically (every 30 minutes — see watering_widget_info.xml,
/// which is the platform-enforced floor regardless of what's configured),
/// so a call here is "make it fresh right now", not the only way it ever
/// updates.
class WidgetService {
  static const _androidWidgetName = 'WateringWidgetProvider';

  /// Call whenever the signed-in plant list actually changes in a way that
  /// could move which plant is most urgent (refresh, mark watered, add a
  /// plant) — the widget has no other way to know that happened before its
  /// own next periodic refresh.
  static Future<void> updateFromPlants(List<Plant> plants) async {
    try {
      if (plants.isEmpty) {
        await HomeWidget.saveWidgetData<String>('plant_name', 'No plants yet');
        await HomeWidget.saveWidgetData<String>('plant_status', 'Open VANYA to scan your first plant');
        await HomeWidget.saveWidgetData<String>('plant_urgency', 'neutral');
      } else {
        final sorted = [...plants]..sort((a, b) => a.nextWateringDue.compareTo(b.nextWateringDue));
        final plant = sorted.first;
        final daysUntil = plant.nextWateringDue.difference(DateTime.now()).inHours / 24;
        final overdue = daysUntil < 0;
        // Same phrasing convention as RemindersScreen's _ReminderTile —
        // this should read as the same product, not a different one.
        final status = overdue
            ? 'Overdue by ${(-daysUntil).ceil()} day(s)'
            : daysUntil < 1
                ? 'Due today'
                : 'Due in ${daysUntil.ceil()} day(s)';
        await HomeWidget.saveWidgetData<String>('plant_name', plant.nickname);
        await HomeWidget.saveWidgetData<String>('plant_status', status);
        await HomeWidget.saveWidgetData<String>('plant_urgency', overdue || daysUntil < 1 ? 'due' : 'ok');
      }
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (e) {
      // Best-effort only, same principle as everywhere else this app
      // touches a device-level integration (notifications, location) — a
      // widget refresh failing must never surface as an app-facing error;
      // worst case it just shows slightly stale data until the next update.
      debugPrint('Failed to update the watering widget: $e');
    }
  }

  /// Call on logout/delete-account — resets the widget to a neutral
  /// "sign in to see your plants" state instead of leaving the previous
  /// session's (now-inaccessible) plant data visible on the home screen.
  static Future<void> clear() async {
    try {
      await HomeWidget.saveWidgetData<String>('plant_name', 'VANYA');
      await HomeWidget.saveWidgetData<String>('plant_status', 'Open VANYA to sign in');
      await HomeWidget.saveWidgetData<String>('plant_urgency', 'neutral');
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (e) {
      debugPrint('Failed to clear the watering widget: $e');
    }
  }
}
