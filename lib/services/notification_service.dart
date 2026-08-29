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
    // BUG (found investigating "I never see any watering notification"):
    // tz.local is NOT the device's local timezone by default — the
    // `timezone` package's initializeTimeZones() hard-sets it to plain UTC
    // (see its env.dart: `_local = _UTC`) and nothing here ever called
    // tz.setLocalLocation to change that. Every "fire at 9am" below was
    // therefore actually firing at 9am UTC — 2:30pm for an IST user, whatever
    // the local offset is for anyone else — which reads as "it just never
    // notifies me" if you're not around at that random hour.
    //
    // Fixed with a fixed-offset Location built from Dart's own
    // DateTime.now().timeZoneOffset (always correct for the device, no
    // extra platform-channel plugin needed) rather than a real IANA
    // location — this won't auto-adjust across a DST transition that
    // happens to fall between "now" and a scheduled date, which is an
    // acceptable gap for a watering reminder (worst case: off by an hour a
    // couple of days a year), not worth a new native dependency to close.
    //
    // SECOND BUG (found after the tz.local fix alone still produced zero
    // notifications on a real device with everything else — permission,
    // battery exemption — correctly set up): this Location's own `.name`
    // isn't just a label. flutter_local_notifications sends it verbatim to
    // Android as `timeZoneName` (see its tz_datetime_mapper.dart), which
    // the native side parses with Java's `ZoneId.of(...)`. Dart's
    // DateTime.timeZoneName is a platform-dependent abbreviation (can be
    // "IST", "GMT+05:30", etc. depending on the device) with no guarantee
    // ZoneId.of() can parse it — an abbreviation like "IST" makes it throw
    // immediately inside the plugin's native zonedSchedule call. Since
    // that call is `unawaited` from AppState with no try/catch anywhere in
    // the chain (see handlePlantSaved), the exception simply vanished —
    // the alarm was never actually scheduled, on every single attempt,
    // regardless of permissions or battery settings.
    //
    // Fixed by building the name in the exact fixed-offset syntax
    // ZoneId.of()'s own Javadoc guarantees it accepts ("UTC+05:30"),
    // computed from the offset directly instead of trusting a
    // platform-supplied abbreviation.
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absOffset = offset.abs();
    final hours = absOffset.inHours.toString().padLeft(2, '0');
    final minutes = (absOffset.inMinutes % 60).toString().padLeft(2, '0');
    final zoneName = 'UTC$sign$hours:$minutes'; // e.g. "UTC+05:30"
    tz.setLocalLocation(
      tz.Location(zoneName, [tz.minTime], [0], [tz.TimeZone(offset.inMilliseconds, isDst: false, abbreviation: zoneName)]),
    );
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
  ///
  /// Wraps the real work in a try/catch: every AppState call site reaches
  /// this via `unawaited(...)` with no try/catch of its own (see
  /// handlePlantSaved/handleMoveToGarden/handleMarkWatered), which is
  /// exactly how a real native-side exception here (see the ZoneId.of
  /// bug fixed in init() above) went completely invisible — the schedule
  /// call was failing on every single attempt with nothing anywhere ever
  /// reporting it. Catching and logging here, once, protects every caller
  /// instead of needing each of them to remember to.
  Future<void> scheduleForPlant(Plant plant) async {
    try {
      await _scheduleForPlant(plant);
    } catch (e) {
      debugPrint('Failed to schedule reminder for ${plant.nickname}: $e');
    }
  }

  Future<void> _scheduleForPlant(Plant plant) async {
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
      // No matchDateTimeComponents: that flag doesn't mean "fires once" —
      // on Android it makes the plugin *recompute* the fire time by
      // searching forward from today for the next date whose month/day
      // matches ours, ignoring the year and ignoring the exact `fireAt`
      // instant we just computed above. Omitting it makes this the plain
      // one-time absolute-instant schedule the comment here always claimed
      // it was.
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
