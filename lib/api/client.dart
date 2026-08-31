import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Thrown on any non-success response envelope. Mirrors the shape of the
/// Error objects thrown by client.js (err.message, err.errorCode,
/// err.statusCode, err.traceId), so error-handling code in screens reads
/// the same way it did in the React version.
class ApiException implements Exception {
  final String message;
  final String errorCode;
  final int statusCode;
  final String traceId;
  ApiException(this.message, this.errorCode, this.statusCode, this.traceId);
  @override
  String toString() => message;
}

class ApiClient {
  // Same env-driven base URL pattern as VITE_API_BASE_URL — set via
  // --dart-define=API_BASE_URL=... at build time, defaulting to the real
  // deployed Render backend so a plain `flutter run`/release build works
  // without any local server or tunnel. Override for local dev against a
  // laptop-hosted backend (e.g. via ngrok) with --dart-define=API_BASE_URL=...
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://vanya-backend-64ja.onrender.com/v1',
  );

  /// Fires whenever an authenticated request comes back 401/UNAUTHORIZED —
  /// the session token has expired (30-day lifetime, no refresh-token
  /// flow) or been invalidated (e.g. a sign-out on this same account
  /// elsewhere bumped token_version — see get_current_user in the
  /// backend's dependencies.py). AppState wires this in bootstrap() to
  /// force a clean re-auth. Without this, every call site's own
  /// catch-and-debugPrint swallowed the 401 silently, so a dead token
  /// just left the UI stuck showing an empty, fresh-looking account
  /// (no plants, no entitlement) with nothing telling the user their
  /// real data wasn't actually gone — just unreachable until they
  /// happened to log out and back in themselves.
  void Function()? onSessionExpired;

  String _generateRequestId() {
    final rand = Random();
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36)).join();
    return 'req-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Map<String, String>? queryParams,
  }) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        ...queryParams,
      });
    }

    final headers = {
      'Content-Type': 'application/json',
      'request-id': _generateRequestId(),
      // Bypasses ngrok's free-tier HTML interstitial warning page, which
      // would otherwise replace the JSON response when API_BASE_URL points
      // at an *.ngrok-free.dev tunnel (e.g. for local backend testing).
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // 55s, not a "normal" API timeout — the deployed backend is a free-tier
    // Render service, which spins down after inactivity and can take
    // 30-60s to cold-start on the very next request. A short/no timeout
    // either hangs forever on a genuinely dead backend, or (worse, and the
    // actual bug this fixed) a too-short one aborts the exact request that
    // was in the middle of waking Render up, so it never gets the chance
    // to complete — the app just looks permanently empty until someone
    // force-closes and retries enough times that a request happens to
    // land on an already-warm instance. This is generous enough to ride
    // out a real cold start while still failing a genuinely unreachable
    // backend instead of hanging indefinitely.
    Future<http.Response> send() {
      switch (method) {
        case 'POST':
          return http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        case 'PUT':
          return http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          return http.delete(uri, headers: headers);
        default:
          return http.get(uri, headers: headers);
      }
    }

    final response = await send().timeout(const Duration(seconds: 55));

    final envelope = jsonDecode(response.body) as Map<String, dynamic>;

    if (envelope['success'] != true) {
      final errorCode = envelope['error'] ?? 'UNKNOWN_ERROR';
      // token != null means this specific request actually sent a Bearer
      // header — a 401 on a request that never carried a token (e.g. a
      // bad /auth/signin attempt) isn't a session expiry, so this stays
      // narrowly scoped to real "your token died" cases.
      if (errorCode == 'UNAUTHORIZED' && token != null) {
        onSessionExpired?.call();
      }
      throw ApiException(
        envelope['message'] ?? 'Request failed',
        errorCode,
        envelope['status_code'] ?? response.statusCode,
        envelope['trace_id'] ?? 'unknown',
      );
    }

    return envelope['data'];
  }

  // ---- Auth ----
  Future<Map<String, dynamic>> signIn(String provider, {String? identityToken, String? deviceUuid}) async {
    final data = await _request('/auth/signin', method: 'POST', body: {
      'provider': provider,
      'identity_token': identityToken,
      'device_uuid': deviceUuid,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> signOut(String token) => _request('/auth/signout', method: 'POST', token: token);

  /// Called after signIn() returns data['status'] == 'restorable' — same
  /// identity, undoes the deletion instead of creating anything new.
  Future<Map<String, dynamic>> restoreAccount(String provider, {String? identityToken, String? deviceUuid}) async {
    final data = await _request('/auth/restore', method: 'POST', body: {
      'provider': provider,
      'identity_token': identityToken,
      'device_uuid': deviceUuid,
    });
    return data as Map<String, dynamic>;
  }

  /// The other half of the restorable choice — explicitly gives up the
  /// restore window and starts a brand-new account under the same identity.
  Future<Map<String, dynamic>> restartAccount(String provider, {String? identityToken, String? deviceUuid}) async {
    final data = await _request('/auth/restart', method: 'POST', body: {
      'provider': provider,
      'identity_token': identityToken,
      'device_uuid': deviceUuid,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> linkIdentity(String token, String identityToken) async {
    final data = await _request('/auth/link', method: 'POST', token: token, body: {'identity_token': identityToken});
    return data as Map<String, dynamic>;
  }

  /// A short-lived, single-use Firebase custom token for the currently
  /// signed-in account — see PaywallScreen._openWebsite. Lets the VANYA
  /// website sign in as this SAME account automatically instead of
  /// showing a bare browser sign-in picker, where it's easy to tap a
  /// different Google account by mistake and end up subscribing on the
  /// wrong one.
  Future<String> createWebHandoffToken(String token) async {
    final data = await _request('/auth/web-handoff-token', method: 'POST', token: token);
    return (data as Map<String, dynamic>)['custom_token'] as String;
  }

  // ---- Plants ----
  Future<List<Plant>> listPlants(
    String token, {
    bool? isIndoor,
    bool? isPetSafe,
    bool? isAirPurifying,
    String? careDifficulty,
    String? lightNeeds,
    String status = 'active',
  }) async {
    final query = <String, String>{'status': status};
    if (isIndoor != null) query['is_indoor'] = isIndoor.toString();
    if (isPetSafe != null) query['is_pet_safe'] = isPetSafe.toString();
    if (isAirPurifying != null) query['is_air_purifying'] = isAirPurifying.toString();
    if (careDifficulty != null) query['care_difficulty'] = careDifficulty;
    if (lightNeeds != null) query['light_needs'] = lightNeeds;

    final data = await _request('/plants', token: token, queryParams: query);
    return (data['plants'] as List).map((p) => Plant.fromJson(p)).toList();
  }

  Future<Map<String, dynamic>> createPlant(String token, Map<String, dynamic> plantInput) async {
    final data = await _request('/plants', method: 'POST', token: token, body: plantInput);
    return data as Map<String, dynamic>;
  }

  /// Promotes a wishlist plant into the active garden — costs a garden
  /// plant slot, not a new identification (see plants_router.py).
  Future<Plant> moveToGarden(String token, String plantId) async {
    final data = await _request('/plants/$plantId/move-to-garden', method: 'POST', token: token);
    return Plant.fromJson(data as Map<String, dynamic>);
  }

  Future<Plant> updatePlant(String token, String plantId, Map<String, dynamic> update) async {
    final data = await _request('/plants/$plantId', method: 'PUT', token: token, body: update);
    return Plant.fromJson(data);
  }

  Future<void> deletePlant(String token, String plantId) =>
      _request('/plants/$plantId', method: 'DELETE', token: token);

  Future<String> uploadPlantPhoto(String token, String plantId, String imageBase64) async {
    final data = await _request(
      '/plants/$plantId/photo',
      method: 'POST',
      token: token,
      body: {'image_base64': imageBase64},
    );
    return data['photo_url'];
  }

  /// Growth Journey — dated, named photo memories on a plant's growth
  /// timeline (Green Thumb-and-up, see plans.dart). Works for wishlist
  /// plants too, same as every other plant-scoped endpoint.
  Future<List<GrowthMemory>> listGrowthMemories(String token, String plantId) async {
    final data = await _request('/plants/$plantId/growth-memories', token: token);
    return (data['memories'] as List).map((m) => GrowthMemory.fromJson(m)).toList();
  }

  Future<GrowthMemory> createGrowthMemory(String token, String plantId, {required String name, String? note, required String imageBase64}) async {
    final data = await _request(
      '/plants/$plantId/growth-memories',
      method: 'POST',
      token: token,
      body: {'name': name, 'note': note, 'image_base64': imageBase64},
    );
    return GrowthMemory.fromJson(data);
  }

  Future<void> deleteGrowthMemory(String token, String plantId, String memoryId) =>
      _request('/plants/$plantId/growth-memories/$memoryId', method: 'DELETE', token: token);

  /// Exactly one of preset/imageBase64 — see GrowthBackgroundInput in
  /// schemas/plant.py. Returns the new growth_background value to store
  /// on the local Plant (either `"preset:<key>"` or the uploaded photo's URL).
  Future<String?> setGrowthBackground(String token, String plantId, {String? preset, String? imageBase64}) async {
    final data = await _request(
      '/plants/$plantId/growth-background',
      method: 'PUT',
      token: token,
      body: {if (preset != null) 'preset': preset, if (imageBase64 != null) 'image_base64': imageBase64},
    );
    return data['growth_background'];
  }

  Future<DiagnosisResult?> getLatestDiagnosis(String token, String plantId) async {
    final data = await _request('/plants/$plantId/diagnoses/latest', token: token);
    if (data['has_diagnosis'] != true) return null;
    return DiagnosisResult.fromJson(data);
  }

  Future<CareCalculators> getCareCalculators(
    String token,
    String plantId, {
    int? potDiameterCm,
    String? season,
    String? roomLight,
    double? latitude,
    double? longitude,
  }) async {
    final query = <String, String>{};
    if (potDiameterCm != null) query['pot_diameter_cm'] = potDiameterCm.toString();
    if (season != null) query['season'] = season;
    if (roomLight != null) query['room_light'] = roomLight;
    if (latitude != null) query['latitude'] = latitude.toString();
    if (longitude != null) query['longitude'] = longitude.toString();
    final data = await _request('/plants/$plantId/calculators', token: token, queryParams: query);
    return CareCalculators.fromJson(data as Map<String, dynamic>);
  }

  /// Season + temperature for a raw lat/long, no plant needed — lets the
  /// Care Calculator screen show what "auto-detect from your location"
  /// resolves to right after location is granted, not just after Calculate.
  Future<LocationWeatherPreview> getLocationWeatherPreview(String token, double latitude, double longitude) async {
    final data = await _request(
      '/plants/weather-preview',
      token: token,
      queryParams: {'latitude': latitude.toString(), 'longitude': longitude.toString()},
    );
    return LocationWeatherPreview.fromJson(data as Map<String, dynamic>);
  }

  // ---- AI Vision ----
  Future<IdentifyResult> identifyPlant(String token, String imageBase64) async {
    final data = await _request('/ai/identify', method: 'POST', token: token, body: {'image_base64': imageBase64});
    return IdentifyResult.fromJson(data);
  }

  Future<DiagnosisResult> diagnosePlant(
    String token,
    String plantId,
    String fullPlantImageBase64,
    String closeupImageBase64,
  ) async {
    final data = await _request('/ai/diagnose', method: 'POST', token: token, body: {
      'plant_id': plantId,
      'full_plant_image_base64': fullPlantImageBase64,
      'closeup_image_base64': closeupImageBase64,
    });
    return DiagnosisResult.fromJson(data);
  }

  // NOTE: no billing/purchase endpoints here — this app never sells
  // subscriptions directly (see paywall_screen.dart). Entitlement state
  // (which the website's checkout flow updates server-side via Razorpay
  // webhooks) is read the normal way, below.

  // ---- Entitlement ----
  Future<Entitlement> getEntitlement(String token) async {
    final data = await _request('/entitlement', token: token);
    return Entitlement.fromJson(data);
  }

  // ---- Analytics ----
  // Best-effort — callers (AppState.trackEvent) swallow failures, since a
  // broken analytics pipeline must never surface as a user-facing error in
  // the feature it's measuring.
  Future<void> logEvent(String token, String eventName, {Map<String, dynamic>? properties}) =>
      _request('/analytics/event', method: 'POST', token: token, body: {
        'event_name': eventName,
        if (properties != null) 'properties': properties,
      });

  // ---- Account ----
  /// Returns {"reminders_enabled": bool, "name": String?} — name is the
  /// display name captured at sign-in (Google always sends one; Apple
  /// only on that identity's first-ever sign-in) or set manually via
  /// updatePreferences below. null means nothing's been captured yet.
  Future<Map<String, dynamic>> getPreferences(String token) async {
    final data = await _request('/users/preferences', token: token);
    return data as Map<String, dynamic>;
  }

  /// name: omit/null leaves the stored name untouched; '' clears it back
  /// to no name; anything else replaces it.
  Future<Map<String, dynamic>> updatePreferences(String token, bool remindersEnabled, {String? name}) async {
    final data = await _request('/users/preferences', method: 'PUT', token: token, body: {
      'reminders_enabled': remindersEnabled,
      if (name != null) 'name': name,
    });
    return data as Map<String, dynamic>;
  }

  /// Returns the raw {"restorable_until": "..."} data — see
  /// AppState.handleDeleteAccount, which parses it into a DateTime so the
  /// caller can tell the user exactly how long they have to change their mind.
  Future<Map<String, dynamic>> deleteAccount(String token) async {
    final data = await _request('/account', method: 'DELETE', token: token);
    return data as Map<String, dynamic>;
  }
}
