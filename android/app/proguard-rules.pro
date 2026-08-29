# flutter_local_notifications ships no consumer ProGuard/R8 rules of its
# own (confirmed: nothing under its android/ directory). Its internal
# scheduled-notification cache is (de)serialized with Gson via
# `new TypeToken<ArrayList<NotificationDetails>>() {}` — Gson's TypeToken
# reads the actual generic argument off that anonymous class's *generic
# signature* via reflection at runtime. R8's default release shrinking
# (which Flutter enables by default for `flutter build apk --release` —
# nothing here opts into it explicitly, it's just Flutter's own default)
# strips that signature unless told to keep it, which throws
# `IllegalStateException: Missing type parameter` the moment the plugin
# tries to schedule anything — silently, if the call site doesn't wrap it
# (see NotificationService.scheduleForPlant's own try/catch, added after
# this was found). This is what made every watering-reminder notification
# fail in every release build, regardless of permissions or device battery
# settings — a debug build never showed it, since R8 shrinking only runs
# for release.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# Keeps the plugin's own model classes (NotificationDetails and friends)
# with their field names intact — Gson serializes/deserializes them by
# reflecting on field names, which R8 would otherwise be free to rename.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
