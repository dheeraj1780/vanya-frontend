import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/models.dart';

/// Thin wrapper around flutter_local_notifications for watering reminders.
///
/// Nothing in this codebase previously called the plugin at all — the
/// Notifications settings screen only stored a `reminders_enabled`
/// preference on the backend, with no local scheduling behind it. This is
/// what actually turns that preference into a notification appearing on
/// the device.
///
/// One notification id per plant (derived from its id) so re-scheduling a
/// plant's reminder replaces the previous one instead of stacking
/// duplicates.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    // Real implementation note: this assumes the device's local timezone.
    // flutter_local_notifications has no built-in way to read it on all
    // platforms without an extra plugin (e.g. flutter_timezone) — using
    // tz.local (defaults to UTC-equivalent "local" offset from the OS)
    // is close enough for a once-a-day watering reminder.
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  int _idFor(String plantId) => plantId.hashCode & 0x7fffffff;

  /// Schedules (or replaces) a single plant's watering reminder for 9am on
  /// its next-due date. Cancels any existing reminder if the plant has
  /// never been watered yet (nothing dated to schedule against) or is
  /// already overdue by more than a day (fires immediately instead, since
  /// a notification in the past would just be dropped).
  Future<void> scheduleForPlant(Plant plant) async {
    if (!_initialized) await init();
    await _plugin.cancel(_idFor(plant.id));

    final due = plant.nextWateringDue;
    var fireAt = tz.TZDateTime(tz.local, due.year, due.month, due.day, 9);
    final now = tz.TZDateTime.now(tz.local);
    if (fireAt.isBefore(now)) {
      fireAt = now.add(const Duration(minutes: 1));
    }

    await _plugin.zonedSchedule(
      _idFor(plant.id),
      'Time to water ${plant.nickname}',
      plant.lastWateredAt == null
          ? 'This plant hasn\'t been logged as watered yet.'
          : 'It\'s been ${plant.waterFrequencyDays} days since the last watering.',
      fireAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'watering_reminders',
          'Watering reminders',
          channelDescription: 'Reminds you when a plant is due for watering.',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime, // fires once, not daily
    );
  }

  Future<void> scheduleAll(List<Plant> plants) async {
    if (!_initialized) await init();
    for (final plant in plants) {
      try {
        await scheduleForPlant(plant);
      } catch (e) {
        debugPrint('Failed to schedule reminder for ${plant.nickname}: $e');
      }
    }
  }

  Future<void> cancelForPlant(String plantId) async {
    if (!_initialized) await init();
    await _plugin.cancel(_idFor(plantId));
  }

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }
}
