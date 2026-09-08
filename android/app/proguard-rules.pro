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

# Firebase Auth + Android Credential Manager + Google Identity Services —
# added while debugging "[16] Account reauth failed" on the Play Store
# -distributed build (see git history for the full investigation). Not
# confirmed as the actual fix (this app's sideloaded release builds,
# which have the exact same R8 shrinking applied, never showed this
# failure) but a commonly-cited cause for this class of Credential
# Manager error elsewhere, cheap to rule out, and consistent with this
# project's own prior history of R8 silently stripping a reflection-
# dependent third-party class (see the flutter_local_notifications
# comment above this one) — worth keeping regardless.
-keep class com.google.firebase.auth.** { *; }
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
