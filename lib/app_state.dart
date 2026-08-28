import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/client.dart';
import 'models/models.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';

/// Mirrors every piece of state App.jsx held in useState, plus every
/// handler function — goTo, refreshPlants, refreshEntitlement,
/// handleSignedIn, handleLogout, handleLinkAccount, handlePlantSaved,
/// handleMarkWatered, handleDiagnosisResult, handleAppResumed.
class AppState extends ChangeNotifier {
  static const _sessionKey = 'plant_companion_session_token';
  static const _isGuestKey = 'plant_companion_is_guest';
  static const _deviceUuidKey = 'plant_companion_device_uuid';

  final ApiClient api = ApiClient();
  late SharedPreferences _prefs;

  String screen = 'welcome';
  String returnTo = 'home';
  // PaywallScreen's own entry point, stashed only for the "Sign in to
  // subscribe" -> GuestGate -> back-to-paywall detour. That detour sets
  // returnTo='paywall' (so GuestGate's own back-navigation lands back on
  // the paywall to finish the purchase) — but that leaves `returnTo`
  // self-referential once you're actually back on the paywall, so its own
  // close/"Not now" buttons need a real fallback rather than "go to
  // myself". See PaywallScreen's dismiss handler.
  String? paywallReturnTo;

  String? token;
  bool isGuest = false;
  List<Plant> plants = [];
  // Plants identified but not yet given a garden slot — a separate list
  // from `plants` (which is always status=active), loaded lazily (only
  // when the Wishlist tab of MyPlantsScreen is actually opened) since most
  // sessions never look at it.
  List<Plant> wishlist = [];
  String? selectedPlantId;
  DiagnosisResult? diagnosisResult;
  Entitlement? entitlement;
  String guestGateReason = '';
  // Display name for the Home greeting — see loadReminderPreference/
  // updateUserName. null means nothing captured/set yet, not an error;
  // every screen that shows it needs to handle that gracefully.
  String? userName;

  // Smart Filters — applied server-side via GET /plants query params
  // (see api/client.dart's listPlants). Null means "no filter on this field".
  bool? filterIsIndoor;
  bool? filterIsPetSafe;
  bool? filterIsAirPurifying;
  String? filterCareDifficulty;
  String? filterLightNeeds;

  bool get hasActiveFilters =>
      filterIsIndoor != null ||
      filterIsPetSafe != null ||
      filterIsAirPurifying != null ||
      filterCareDifficulty != null ||
      filterLightNeeds != null;

  // Mirrors the server's `reminders_enabled` preference (see
  // NotificationSettingsScreen/RemindersScreen, which read/write it via
  // GET/PUT /users/preferences) so handleMarkWatered below knows whether to
  // reschedule that plant's local notification.
  bool remindersEnabled = false;

  /// RemindersScreen/NotificationSettingsScreen both used to poke the
  /// `remindersEnabled` field directly with no notifyListeners() — harmless
  /// for their own toggle (each forces its own rebuild via local setState
  /// regardless), but fragile for anywhere else that might ever read this.
  void setRemindersEnabled(bool value) {
    remindersEnabled = value;
    notifyListeners();
  }

  Plant? get selectedPlant {
    if (selectedPlantId == null) return null;
    try {
      return plants.firstWhere((p) => p.id == selectedPlantId);
    } catch (_) {
      return null;
    }
  }

  // Growth Journey works for wishlist plants too (see GrowthJourneyScreen),
  // unlike selectedPlant above which every other screen (reminders,
  // diagnose, calculators) correctly assumes is an active garden plant —
  // kept as its own field rather than broadening selectedPlant's search to
  // both lists, which would be a real behavior change for those screens.
  String? growthJourneyPlantId;

  Plant? get growthJourneyPlant {
    if (growthJourneyPlantId == null) return null;
    try {
      return [...plants, ...wishlist].firstWhere((p) => p.id == growthJourneyPlantId);
    } catch (_) {
      return null;
    }
  }

  /// Called once from main.dart after Firebase.initializeApp(). Mirrors the
  /// useEffect(() => { if (token) {...} }, []) bootstrap in App.jsx — if a
  /// session already exists (returning user), skip onboarding entirely.
  Future<void> bootstrap() async {
    api.onSessionExpired = _handleSessionExpired;
    _prefs = await SharedPreferences.getInstance();
    token = _prefs.getString(_sessionKey);
    isGuest = _prefs.getBool(_isGuestKey) ?? false;

    if (token != null) {
      screen = 'home';
      // Fire-and-forget, same tolerance as the React version — a failed
      // refresh shouldn't block showing the (possibly stale) cached UI.
      // Chained (not run in parallel with refreshPlants) so reminders are
      // scheduled against the real plant list, not the empty startup one.
      unawaited(refreshPlants().then((_) => loadReminderPreference()));
      unawaited(refreshEntitlement());
    }
    notifyListeners();
  }

  // Home / My Plants / Reminders share one persistent bottom-nav shell (see
  // main.dart's RootRouter/_TabShell) — kept here too so goTo/goBack can
  // reason about tab switches without main.dart handing that knowledge back
  // in.
  static const tabScreens = {'home', 'myPlants', 'reminders'};

  // This app has no Navigator route stack — every screen change is just
  // this `screen` string flipping (see RootRouter in main.dart) — so
  // without this, the system back button/edge-swipe gesture had nothing to
  // retrace and fell straight through to closing the app (BUGID-S002).
  // Every goTo() records where it left from; goBack() (called by every
  // on-screen Back button *and* by the PopScope in main.dart wired to the
  // system back button/gesture) retraces it.
  final List<String> _screenHistory = [];

  void goTo(String target, {String? withReturnTo}) {
    if (withReturnTo != null) returnTo = withReturnTo;
    if (target != screen) {
      // Switching between the three bottom-nav tabs replaces the current
      // position instead of stacking — otherwise rapid tab-tapping would
      // turn "back" into "replay every tab I ever tapped", which isn't how
      // bottom-nav back behavior normally works.
      final bothTabs = tabScreens.contains(screen) && tabScreens.contains(target);
      if (!bothTabs) _screenHistory.add(screen);
    }
    screen = target;
    notifyListeners();
  }

  /// Whether there's somewhere for goBack() to actually go — false at a
  /// true root (nothing recorded, already on the Home tab), which is
  /// exactly when the system back button/gesture should be left to do its
  /// normal thing (exit the app) instead of being intercepted.
  bool get canGoBack => _screenHistory.isNotEmpty || (tabScreens.contains(screen) && screen != 'home');

  /// The "go back" every on-screen Back button now calls, and what the
  /// system back button/edge-swipe gesture is rerouted into via PopScope —
  /// so both retrace the exact same path instead of the gesture having a
  /// separate, harsher "just exit" behavior. `fallback` only matters for a
  /// screen reached with no recorded history (e.g. straight after a cold
  /// start).
  void goBack({String fallback = 'home'}) {
    if (_screenHistory.isNotEmpty) {
      screen = _screenHistory.removeLast();
    } else if (tabScreens.contains(screen) && screen != 'home') {
      screen = 'home'; // standard bottom-nav pattern: land on Home before the next back exits
    } else {
      screen = fallback;
    }
    notifyListeners();
  }

  /// Hard reset to `target` with the back history wiped — for transitions
  /// after which nothing before them is a valid back target any more (the
  /// session that got you there is gone): signing out, deleting the
  /// account. Plain goTo() would instead leave those now-stale screens
  /// reachable via the next back button press/gesture.
  void resetTo(String target) {
    _screenHistory.clear();
    screen = target;
    notifyListeners();
  }

  Future<void> refreshPlants() async {
    if (token == null) return;
    try {
      plants = await api.listPlants(
        token!,
        isIndoor: filterIsIndoor,
        isPetSafe: filterIsPetSafe,
        isAirPurifying: filterIsAirPurifying,
        careDifficulty: filterCareDifficulty,
        lightNeeds: filterLightNeeds,
      );
      notifyListeners();
      unawaited(WidgetService.updateFromPlants(plants));
    } catch (e) {
      debugPrint('Failed to refresh plants: $e');
    }
  }

  /// Applies the given Smart Filters (each null clears that field) and
  /// re-fetches. Called from FiltersScreen; a bare `applyFilters()` with no
  /// arguments clears every filter.
  Future<void> applyFilters({
    bool? isIndoor,
    bool? isPetSafe,
    bool? isAirPurifying,
    String? careDifficulty,
    String? lightNeeds,
  }) async {
    filterIsIndoor = isIndoor;
    filterIsPetSafe = isPetSafe;
    filterIsAirPurifying = isAirPurifying;
    filterCareDifficulty = careDifficulty;
    filterLightNeeds = lightNeeds;
    await refreshPlants();
  }

  /// Loads the reminders_enabled preference (and, alongside it, the
  /// display name — same endpoint, see api.getPreferences) and, if
  /// reminders are on, (re)schedules every plant's local notification —
  /// the one place that actually connects the stored preference to a
  /// real notification being scheduled.
  Future<void> loadReminderPreference() async {
    if (token == null) return;
    try {
      final data = await api.getPreferences(token!);
      remindersEnabled = data['reminders_enabled'];
      userName = data['name'];
      notifyListeners();
      if (remindersEnabled) {
        await NotificationService.instance.scheduleAll(plants);
      } else {
        await NotificationService.instance.cancelAll();
      }
    } catch (e) {
      debugPrint('Failed to load reminder preference: $e');
    }
  }

  /// Saves a manually-set/edited display name (Settings' "Name" field) —
  /// the fallback for accounts that never captured one automatically
  /// (Apple only sends one on that identity's very first sign-in ever;
  /// guests have no identity to pull one from at all) and for anyone who
  /// just wants to change what's there. Pass null or '' to clear it back
  /// to no name — the Home greeting then falls back to a plain "Good
  /// morning" with no name, same as before this feature existed.
  Future<void> updateUserName(String? name) async {
    final data = await api.updatePreferences(token!, remindersEnabled, name: name ?? '');
    userName = data['name'];
    notifyListeners();
  }

  /// Fire-and-forget analytics — see analytics_router.py. No-ops before a
  /// session exists (nothing in this app is reachable pre-sign-in/guest
  /// anyway, see SignInScreen's guest flow) and swallows any failure so a
  /// flaky network never surfaces as a user-facing error in the feature
  /// being measured.
  void trackEvent(String eventName, {Map<String, dynamic>? properties}) {
    final t = token;
    if (t == null) return;
    unawaited(api.logEvent(t, eventName, properties: properties).catchError((e) {
      debugPrint('Analytics event "$eventName" failed to log: $e');
    }));
  }

  Future<void> refreshWishlist() async {
    if (token == null) return;
    try {
      wishlist = await api.listPlants(token!, status: 'wishlist');
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh wishlist: $e');
    }
  }

  Future<void> refreshEntitlement() async {
    if (token == null) return;
    try {
      entitlement = await api.getEntitlement(token!);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh entitlement: $e');
    }
  }

  Future<String> getOrCreateDeviceUuid() async {
    var uuid = _prefs.getString(_deviceUuidKey);
    if (uuid == null) {
      // Same simple random-UUID approach as the React version's
      // crypto.randomUUID() — no external package needed for this.
      uuid = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
          (1000 + DateTime.now().millisecond).toRadixString(36);
      await _prefs.setString(_deviceUuidKey, uuid);
    }
    return uuid;
  }

  Future<void> handleSignedIn(Map<String, dynamic> signInData) async {
    token = signInData['session_token'];
    isGuest = signInData['is_guest'];
    await _prefs.setString(_sessionKey, token!);
    await _prefs.setBool(_isGuestKey, isGuest);

    // resetTo, not goTo: signing in is a point of no return like logout/
    // delete-account (see resetTo's docstring) — plain goTo() would push
    // 'signin' onto the back history, so the very first system-back press
    // after landing on Home went straight back to the sign-in screen
    // instead of exiting the app.
    resetTo('home');
    await refreshPlants();
    await refreshEntitlement();
    await loadReminderPreference();
  }

  /// BUGID-S001: on-device this looked like "Log out" just didn't work — no
  /// spinner (see settings_screen.dart's loading state, added alongside
  /// this) made a slow/cold-starting backend call look like a dead tap, and
  /// worse, *every* step below used to run unguarded: if SharedPreferences
  /// or the notification plugin threw partway through, the function exited
  /// right there and `screen = 'signin'` at the end never ran — the app
  /// just silently stayed put. Each local-cleanup step is now independently
  /// best-effort so one failing can never block the sign-out the user
  /// actually asked for, and the sign-out call itself is time-boxed so a
  /// slow network can't make the button look stuck.
  Future<void> handleLogout() async {
    try {
      if (token != null) await api.signOut(token!).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Sign-out request failed (clearing local session anyway): $e');
    }
    await _signOutOfProviders();
    try {
      await _prefs.remove(_sessionKey);
      await _prefs.remove(_isGuestKey);
    } catch (e) {
      debugPrint('Clearing stored session failed (proceeding anyway): $e');
    }
    token = null;
    isGuest = false;
    plants = [];
    entitlement = null;
    remindersEnabled = false;
    userName = null;
    try {
      await NotificationService.instance.cancelAll();
    } catch (e) {
      debugPrint('Cancelling reminders failed (proceeding anyway): $e');
    }
    unawaited(WidgetService.clear());
    resetTo('signin');
  }

  /// Consumed once by SignInScreen.initState (which reads it, shows it,
  /// then nulls it back out) — set only by _handleSessionExpired below, so
  /// this stays null on every ordinary path to the sign-in screen.
  String? sessionExpiredMessage;

  /// Wired to api.onSessionExpired in bootstrap() — fires the moment any
  /// authenticated call comes back 401. Deliberately NOT the same as
  /// handleLogout: this skips the /auth/signout call (the token that
  /// would authorize it is exactly what's already dead server-side, so
  /// that call would just 401 again) and leaves a message behind so the
  /// sign-in screen reads as "please sign in again", not a silent,
  /// unexplained wipe of everything that was on screen a moment ago.
  Future<void> _handleSessionExpired() async {
    if (token == null) return; // already signed out — nothing to do
    await _signOutOfProviders();
    try {
      await _prefs.remove(_sessionKey);
      await _prefs.remove(_isGuestKey);
    } catch (e) {
      debugPrint('Clearing stored session failed (proceeding anyway): $e');
    }
    token = null;
    isGuest = false;
    plants = [];
    entitlement = null;
    remindersEnabled = false;
    userName = null;
    try {
      await NotificationService.instance.cancelAll();
    } catch (e) {
      debugPrint('Cancelling reminders failed (proceeding anyway): $e');
    }
    unawaited(WidgetService.clear());
    sessionExpiredMessage = 'Your session expired — sign in again to pick up right where you left off.';
    resetTo('signin');
  }

  /// Signs out of Firebase Auth *and* the native Google Sign-In SDK.
  /// Firebase's own signOut() does NOT clear Google's cached session — left
  /// alone, the next "Continue with Google" silently re-picks whichever
  /// Google account was used last instead of showing the account picker,
  /// so switching accounts (or just wanting a fresh choice) was impossible
  /// after logging out. Both best-effort, same reasoning as everywhere
  /// else in this method: a provider SDK hiccup can't block the sign-out
  /// the user actually asked for.
  Future<void> _signOutOfProviders() async {
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Firebase sign-out failed (proceeding anyway): $e');
    }
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Google sign-out failed (proceeding anyway): $e');
    }
    // BUG-H001: signOut() alone wasn't enough — Google Play Services on
    // Android can still silently re-hand back the same account on the next
    // signIn() call even after signOut(), a known quirk of the plugin/OS
    // account cache, not something this app controls otherwise. disconnect()
    // fully revokes the granted OAuth scopes, which reliably forces the real
    // account chooser (with every Google account on the device, not just the
    // last-used one) on the next sign-in. Throws if there was never a Google
    // session to revoke (e.g. a guest or Apple-only user) — safe to ignore,
    // same tolerance as signOut() above.
    try {
      await GoogleSignIn().disconnect();
    } catch (e) {
      debugPrint('Google disconnect failed (proceeding anyway): $e');
    }
  }

  /// Permanently deletes the account server-side (DELETE /account — see
  /// account_service.py) — the one step here that's allowed to actually
  /// fail the whole operation, since unlike everything below it can't be
  /// silently skipped. Confirmation happens in the calling screen; by the
  /// time this runs it's final. Required by Play Store policy: any app
  /// that lets a user create an account must offer in-app deletion, not
  /// just a support-ticket process.
  ///
  /// Deliberately does NOT switch `screen` itself (unlike handleLogout) —
  /// the caller shows a "deleted" confirmation first (BUGID-S003 asked for
  /// one; there was none before), then navigates once that's dismissed, so
  /// the success screen doesn't get yanked out from under it mid-read.
  /// Same best-effort reasoning as handleLogout applies to everything past
  /// the delete call: the account is already gone server-side at that
  /// point, so a SharedPreferences/notification hiccup here must never
  /// surface as "could not delete your account" — that would be false.
  ///
  /// Returns when the 24-hour restore window closes — the account isn't
  /// actually gone-gone until then (see the backend's
  /// ACCOUNT_RESTORE_WINDOW): signing back in with the same identity
  /// before this offers a restore-or-start-fresh choice instead of a
  /// normal sign-in (see SignInScreen._handleRestorable).
  Future<DateTime> handleDeleteAccount() async {
    final data = await api.deleteAccount(token!);
    final restorableUntil = parseUtcDateTime(data['restorable_until']);
    await _signOutOfProviders();
    try {
      await _prefs.remove(_sessionKey);
      await _prefs.remove(_isGuestKey);
    } catch (e) {
      debugPrint('Clearing stored session failed (proceeding anyway): $e');
    }
    token = null;
    isGuest = false;
    plants = [];
    entitlement = null;
    remindersEnabled = false;
    userName = null;
    try {
      await NotificationService.instance.cancelAll();
    } catch (e) {
      debugPrint('Cancelling reminders failed (proceeding anyway): $e');
    }
    unawaited(WidgetService.clear());
    notifyListeners();
    return restorableUntil;
  }

  /// Real call to POST /auth/link — attaches the currently authenticated
  /// (guest) user_id to a real Firebase-verified identity instead of
  /// creating a second, disconnected account.
  Future<Map<String, dynamic>> handleLinkAccount(String identityToken) async {
    final data = await api.linkIdentity(token!, identityToken);
    await _prefs.setBool(_isGuestKey, false);
    isGuest = false;
    notifyListeners();
    return data;
  }

  /// Called when a Link attempt fails specifically because the identity
  /// already belongs to a different, real account (error code
  /// IDENTITY_ALREADY_LINKED) and the user explicitly chose to abandon
  /// this guest session and sign into that existing account instead of
  /// being left stuck with no path forward. Reuses the identityToken
  /// already obtained for the failed link attempt — no need to re-prompt
  /// Google/Apple's picker again. This does NOT merge the two accounts:
  /// the guest session's plants/data stay on the now-unreachable guest
  /// account, exactly the tradeoff the confirmation dialog warns about
  /// before this gets called.
  Future<void> switchToExistingAccount(String identityToken) async {
    final data = await api.signIn('firebase', identityToken: identityToken);
    await handleSignedIn(data);
  }

  void handlePlantSaved(Plant newPlant) {
    plants = [newPlant, ...plants];
    unawaited(refreshEntitlement());
    unawaited(WidgetService.updateFromPlants(plants));
    if (remindersEnabled) unawaited(NotificationService.instance.scheduleForPlant(newPlant));
    goTo('home');
  }

  /// Same identify flow, different destination — status=wishlist plants
  /// don't get reminders scheduled (they're not an active plant to water
  /// yet) and don't affect the home dashboard, only the Wishlist tab.
  void handleWishlistItemSaved(Plant newItem) {
    wishlist = [newItem, ...wishlist];
    unawaited(refreshEntitlement());
    goTo('myPlants');
  }

  /// Promotes a wishlist plant into the active garden — costs a garden
  /// plant slot server-side, not a new identification (see
  /// plants_router.py's /move-to-garden).
  Future<void> handleMoveToGarden(String plantId) async {
    final moved = await api.moveToGarden(token!, plantId);
    wishlist = wishlist.where((p) => p.id != plantId).toList();
    plants = [moved, ...plants];
    if (remindersEnabled) unawaited(NotificationService.instance.scheduleForPlant(moved));
    unawaited(refreshEntitlement());
    notifyListeners();
  }

  Future<void> handleMarkWatered(String plantId) async {
    final now = DateTime.now();
    // Optimistic update, same as the React version.
    plants = plants.map((p) => p.id == plantId ? p.copyWith(lastWateredAt: now) : p).toList();
    notifyListeners();
    unawaited(WidgetService.updateFromPlants(plants));
    // Watering just pushed this plant's due date out — reschedule its
    // reminder against the new date instead of leaving the stale one armed.
    if (remindersEnabled) {
      final watered = plants.firstWhere((p) => p.id == plantId);
      unawaited(NotificationService.instance.scheduleForPlant(watered));
    }
    try {
      // .toUtc() matters: the backend stores every timestamp as naive UTC
      // and treats any datetime it receives as already being UTC (see
      // parseUtcDateTime's docstring) — sending local wall-clock time
      // here (e.g. 8:00 PM IST) would get stored as if it were 8:00 PM
      // UTC, skewing every future "next watering due" calculation for
      // this plant by the device's UTC offset.
      await api.updatePlant(token!, plantId, {'last_watered_at': now.toUtc().toIso8601String()});
    } catch (e) {
      debugPrint('Failed to sync watered status: $e');
      unawaited(refreshPlants()); // reconcile with server truth if the write failed
    }
  }

  /// Removes a plant — DELETE /plants/:id (also deletes its diagnosis
  /// history server-side, per plant_service.py). Confirmation happens in
  /// the calling screen; by the time this runs it's final.
  Future<void> handleDeletePlant(String plantId) async {
    await api.deletePlant(token!, plantId);
    plants = plants.where((p) => p.id != plantId).toList();
    if (selectedPlantId == plantId) selectedPlantId = null;
    unawaited(NotificationService.instance.cancelForPlant(plantId));
    unawaited(refreshEntitlement());
    unawaited(WidgetService.updateFromPlants(plants));
    goTo('myPlants');
  }

  /// Replaces one plant in-place, in whichever of plants/wishlist actually
  /// holds it (a plant is never in both) — the generic version of the
  /// copyWith-then-splice pattern handleMarkWatered/etc. each do inline for
  /// their own one field. Used by GrowthJourneyScreen's background picker,
  /// which needs to update growthBackground without touching anything else.
  void updatePlantLocally(Plant updated) {
    if (plants.any((p) => p.id == updated.id)) {
      plants = plants.map((p) => p.id == updated.id ? updated : p).toList();
    } else if (wishlist.any((p) => p.id == updated.id)) {
      wishlist = wishlist.map((p) => p.id == updated.id ? updated : p).toList();
    }
    notifyListeners();
  }

  /// Same DELETE /plants/:id as handleDeletePlant, but for a wishlist card
  /// removed inline (no detail screen, no navigation afterward) — never had
  /// a reminder scheduled in the first place, since wishlist plants aren't
  /// "due for watering."
  Future<void> handleRemoveFromWishlist(String plantId) async {
    await api.deletePlant(token!, plantId);
    wishlist = wishlist.where((p) => p.id != plantId).toList();
    unawaited(refreshEntitlement());
    notifyListeners();
  }

  void handleDiagnosisResult(DiagnosisResult result) {
    diagnosisResult = result;
    unawaited(refreshEntitlement());
    goTo('diagnosisResult');
  }

  /// Called from main.dart whenever the app resumes from the background —
  /// covers "left the app to pay on vanya.app in the browser, came back"
  /// without any purchase-specific event to hook (there's no in-app
  /// purchase completion anymore; see paywall_screen.dart). Cheap no-op
  /// the rest of the time.
  void handleAppResumed() {
    if (token == null) return;
    unawaited(refreshEntitlement());
  }
}

// Dart has no built-in "fire and forget" keyword like JS's bare Promise
// call — this just documents intent the same way a bare `promise.catch()`
// would, without requiring every call site to handle a Future explicitly.
void unawaited(Future<void> future) {}
