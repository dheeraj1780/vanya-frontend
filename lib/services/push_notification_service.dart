import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Receives server-sent ("push") notifications via Firebase Cloud
/// Messaging — feature call-outs, app news, anything sent on demand
/// whenever we decide to, rather than scheduled locally ahead of time from
/// data already on the device.
///
/// This is deliberately separate from [NotificationService]: that one
/// computes and schedules deterministic per-plant watering reminders from
/// data the app already has, tied to the reminders_enabled preference —
/// this one just displays whatever a message tells it to, tied to nothing
/// but the OS notification permission.
///
/// No backend wiring needed for this first cut. Firebase Cloud Messaging's
/// own Console ("Engage > Messaging" > "New campaign") can already reach
/// every installed app instance the moment this is initialized — it
/// doesn't need us to collect or store device tokens anywhere. A backend
/// send path (e.g. targeted by plan tier, or "hasn't added a plant yet")
/// is a separate, later addition, only worth it once real segmentation is
/// needed beyond "send this to everyone right now."
class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();

  // A second FlutterLocalNotificationsPlugin() instance, deliberately not
  // shared with NotificationService's — both are thin Dart-side wrappers
  // over the one native plugin singleton (that's how the package is meant
  // to be used from multiple call sites), so this doesn't double-register
  // or conflict with anything; it just keeps the two services fully
  // independent of each other's internal state.
  final FlutterLocalNotificationsPlugin _localPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'announcements';
  static const _channelName = 'News & feature announcements';
  static const _channelDescription = "Occasional updates about new features and what's new in the app — separate from watering reminders.";

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // BUG (found live: on a fresh install, the OS notification-permission
    // dialog was popping up within seconds of app launch, before the intro
    // video, Welcome screen, or the "Two quick permissions" explanation
    // screen ever appeared — completely bypassing onboarding). This
    // service's own init() runs unconditionally in main(), before any UI
    // exists, so calling FirebaseMessaging's own requestPermission() here
    // fired the real system dialog immediately on a fresh install — the
    // "harmless no-op once granted" reasoning only holds for every launch
    // *after* the first, which is exactly the one that matters.
    //
    // No request call needed here at all: POST_NOTIFICATIONS is a single
    // shared OS permission on Android — PermissionsScreen (onboarding)
    // already asks for it, contextually, in the right place, and FCM
    // messages display correctly once that's granted regardless of which
    // code path did the asking. This service only needs to know the
    // current status to decide whether to bother initializing further, not
    // to request it itself.

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localPlugin.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));

    // FCM's "notification" payload is auto-displayed by the OS only when
    // the app is backgrounded or terminated — while it's open in the
    // foreground, Android/iOS both suppress it and just deliver the raw
    // message to onMessage instead, so a broadcast sent while someone has
    // the app open would otherwise silently never appear. This is what
    // makes it show up regardless of foreground/background state.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Tapping a background/terminated notification, or a cold start from
    // one, both just bring the app to its normal signed-in screen today —
    // nothing payload-specific to route to yet, since these are plain
    // announcements, not deep links into a particular plant/screen. No
    // onBackgroundMessage handler is registered either, deliberately: it's
    // only needed to run Dart code for a *data-only* background message —
    // a plain notification-payload broadcast (title + body) is displayed
    // by the OS itself with zero app code involved while backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});
    await FirebaseMessaging.instance.getInitialMessage();
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return; // data-only message — nothing to display
    try {
      await _localPlugin.show(
        message.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Failed to display foreground announcement: $e');
    }
  }
}
