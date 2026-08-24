import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../api/client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/calculator_result_cards.dart';
import '../widgets/primary_button.dart';

/// Care Calculators — was a Home quick-action tile with an empty onTap.
/// Calls GET /plants/:id/calculators, which computes watering schedule,
/// fertilizer dosing, and light fit specific to the chosen plant (see
/// calculator_service.py on the backend for the formulas + reasoning).
class CalculatorsScreen extends StatefulWidget {
  const CalculatorsScreen({super.key});
  @override
  State<CalculatorsScreen> createState() => _CalculatorsScreenState();
}

class _CalculatorsScreenState extends State<CalculatorsScreen> {
  String? _plantId;
  int? _potDiameterCm;
  String? _season; // null = let the backend infer it (location if set, else Northern-hemisphere calendar guess)
  String? _roomLight;

  double? _latitude;
  double? _longitude;
  String _locationStatus = 'idle'; // idle | loading | located | error
  String _locationError = '';

  // BUG-C001: once location is granted, show what it actually resolves to
  // (place name + season + temperature) instead of leaving the generic
  // "Auto-detect from your location" text as the only feedback.
  bool _previewLoading = false;
  String? _locationName;
  String? _previewSeason;
  double? _previewTemperatureC;

  String _status = 'idle'; // idle | loading | error
  String _errorMessage = '';
  CareCalculators? _result;

  /// Coarse device location, used only to derive season/weather (see
  /// weather_client.py) — never sent anywhere but this one API call.
  Future<void> _useMyLocation() async {
    setState(() {
      _locationStatus = 'loading';
      _locationError = '';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off on this device.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw 'Location permission was denied.';
      }
      // Season/weather don't need up-to-the-second accuracy, so try the
      // cached last-known fix first (instant) before requesting a fresh
      // one — a fresh GPS fix has no default timeout and can hang
      // indefinitely on an emulator or weak signal, which is what was
      // making this feel stuck.
      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          );
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _season = null; // let the backend derive season from this location instead
        _locationStatus = 'located';
      });
      unawaited(_loadLocationPreview());
    } on TimeoutException {
      setState(() {
        _locationStatus = 'error';
        _locationError = 'Could not get a location fix in time. Try again outdoors, or pick a season manually below.';
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'error';
        _locationError = e.toString();
      });
    }
  }

  /// Resolves the just-granted location into something actually worth
  /// showing — a place name (best-effort, via a keyless reverse-geocode
  /// lookup) and the season/temperature it maps to (via the backend, same
  /// weather source the calculator itself uses). Both halves are
  /// independently best-effort: either can fail without blocking the other
  /// or the rest of the screen — this is a preview, not a hard requirement.
  Future<void> _loadLocationPreview() async {
    if (_latitude == null || _longitude == null) return;
    final appState = context.read<AppState>();
    setState(() => _previewLoading = true);
    final weatherFuture = _fetchWeatherPreview(appState, _latitude!, _longitude!);
    final nameFuture = _reverseGeocode(_latitude!, _longitude!);
    final weather = await weatherFuture;
    final name = await nameFuture;
    if (!mounted) return;
    setState(() {
      _previewSeason = weather?.season;
      _previewTemperatureC = weather?.temperatureC;
      _locationName = name;
      _previewLoading = false;
    });
  }

  /// Best-effort wrapper around the backend weather-preview call — a failed
  /// lookup (network hiccup, Open-Meteo down) just means no season/temp
  /// shows in the banner, never a blocking error on this screen.
  Future<LocationWeatherPreview?> _fetchWeatherPreview(AppState appState, double latitude, double longitude) async {
    try {
      return await appState.api.getLocationWeatherPreview(appState.token!, latitude, longitude);
    } catch (_) {
      return null;
    }
  }

  /// BigDataCloud's free "client-side" reverse-geocode endpoint — built for
  /// exactly this use case (no API key, no backend round trip needed).
  /// Best-effort only: on any failure this just means the preview banner
  /// shows season/temperature without a place name, never a blocking error.
  Future<String?> _reverseGeocode(double latitude, double longitude) async {
    try {
      final uri = Uri.parse(
        'https://api-bdc.io/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=en',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final city = (data['city'] as String?)?.trim();
      final locality = (data['locality'] as String?)?.trim();
      final name = (city != null && city.isNotEmpty) ? city : locality;
      return (name != null && name.isNotEmpty) ? name : null;
    } catch (_) {
      return null;
    }
  }

  /// Label for the Season dropdown's "auto" entry — generic phrasing until
  /// location is actually resolved, then the real place/season takes over
  /// so the entry stops claiming "your location" with nothing to show for
  /// it (BUG-C001).
  String get _autoSeasonDropdownLabel {
    if (_locationStatus != 'located') return 'Auto-detect from today\'s date';
    if (_previewLoading) return 'Detecting your location\'s season…';
    if (_previewSeason == null) return 'Auto-detect from your location';
    final seasonLabel = _previewSeason![0].toUpperCase() + _previewSeason!.substring(1);
    return _locationName != null ? '$_locationName · $seasonLabel' : seasonLabel;
  }

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _plantId = appState.selectedPlantId ?? (appState.plants.isNotEmpty ? appState.plants.first.id : null);
  }

  Future<void> _calculate() async {
    final appState = context.read<AppState>();
    if (_plantId == null) return;
    setState(() {
      _status = 'loading';
      _errorMessage = '';
    });
    try {
      final result = await appState.api.getCareCalculators(
        appState.token!,
        _plantId!,
        potDiameterCm: _potDiameterCm,
        season: _season,
        roomLight: _roomLight,
        // Only sent when the season dropdown is left on "auto" — an
        // explicit season pick always wins over location-derived weather.
        latitude: _season == null ? _latitude : null,
        longitude: _season == null ? _longitude : null,
      );
      setState(() {
        _status = 'idle';
        _result = result;
      });
      appState.trackEvent(appState.isGuest ? 'guest_care_used' : 'plantie_care_used');
      unawaited(appState.refreshEntitlement());
    } on ApiException catch (err) {
      setState(() {
        _status = 'error';
        _errorMessage = err.message;
      });
      // This screen previously had no limit-error routing at all — any
      // ApiException, including PLAN_LIMIT_EXCEEDED/GUEST_SIGNIN_REQUIRED,
      // just showed as inline red text. Same routing pattern as
      // AddPlantScreen/DiagnoseScreen now applies here too.
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('care_limit_reached');
        appState.goTo('paywall', withReturnTo: 'calculators');
      } else if (err.errorCode == 'GUEST_SIGNIN_REQUIRED') {
        appState.trackEvent('care_limit_reached');
        appState.guestGateReason = err.message;
        appState.goTo('guestGate', withReturnTo: 'calculators');
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Could not calculate — check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final loading = _status == 'loading';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'home')),
        title: const Text('Care calculators'),
      ),
      body: appState.plants.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Add a plant first — calculators are specific to each plant\'s own profile.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _FieldLabel('Plant'),
                DropdownButtonFormField<String>(
                  initialValue: _plantId,
                  isExpanded: true,
                  items: [for (final p in appState.plants) DropdownMenuItem(value: p.id, child: Text(p.nickname))],
                  onChanged: (v) => setState(() {
                    _plantId = v;
                    _result = null;
                  }),
                ),
                const SizedBox(height: 14),
                _FieldLabel('Pot diameter (cm) — optional'),
                TextFormField(
                  keyboardType: TextInputType.number,
                  style: AppTypography.bodyStrong(AppColors.textOf(context)), // entered value: bold + dark, visibly different from the hint below
                  decoration: InputDecoration(hintText: 'e.g. 18', hintStyle: AppTypography.body(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic)),
                  onChanged: (v) => _potDiameterCm = int.tryParse(v),
                ),
                const SizedBox(height: 14),
                _FieldLabel('Season'),
                DropdownButtonFormField<String?>(
                  initialValue: _season,
                  isExpanded: true,
                  // Placeholder-like entries (the null "auto" option) styled
                  // muted + italic; real picks bold + dark — previously both
                  // looked identical, so a real selection could be mistaken
                  // for the unset default.
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(
                        _autoSeasonDropdownLabel,
                        style: AppTypography.body(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic),
                      ),
                    ),
                    for (final s in const ['spring', 'summer', 'autumn', 'winter'])
                      DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1), style: AppTypography.bodyStrong(AppColors.textOf(context)))),
                  ],
                  onChanged: (v) => setState(() => _season = v),
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  onPressed: _locationStatus == 'loading' ? null : _useMyLocation,
                  icon: _locationStatus == 'located' ? Icons.check_circle_outline : Icons.my_location,
                  label: switch (_locationStatus) {
                    'loading' => 'Getting location…',
                    'located' => 'Using your location for season & weather',
                    _ => 'Use my location for season & weather',
                  },
                ),
                if (_locationStatus == 'error')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_locationError, style: const TextStyle(color: AppColors.accent, fontSize: 11.5)),
                  ),
                // BUG-C001: once location is on, surface what it actually
                // resolved to right here — place name, season, temperature —
                // instead of only the generic "auto-detect" wording above.
                if (_locationStatus == 'located' && _season == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _previewLoading
                                  ? 'Detecting the season for your location…'
                                  : _previewSeason == null
                                      ? 'Location detected — season unavailable right now.'
                                      : [
                                          if (_locationName != null) _locationName!,
                                          _previewSeason![0].toUpperCase() + _previewSeason!.substring(1),
                                          if (_previewTemperatureC != null) '${_previewTemperatureC!.round()}°C',
                                        ].join(' · '),
                              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                _FieldLabel('Room light — optional, for the light fit check'),
                DropdownButtonFormField<String?>(
                  initialValue: _roomLight,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: null, child: Text('Not sure', style: AppTypography.body(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic))),
                    for (final entry in const {'low': 'Low light', 'medium': 'Medium / indirect light', 'bright': 'Bright indirect light', 'direct': 'Direct sun'}.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value, style: AppTypography.bodyStrong(AppColors.textOf(context)))),
                  ],
                  onChanged: (v) => setState(() => _roomLight = v),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: loading ? 'Calculating…' : 'Calculate',
                  loading: loading,
                  onPressed: (_plantId == null || loading) ? null : _calculate,
                ),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_errorMessage, style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
                  ),
                if (_result != null) ...[
                  const SizedBox(height: 22),
                  Text(
                    'For ${_result!.nickname} · ${_result!.season}'
                    '${_result!.locationAware ? ' (from your location' '${_result!.temperatureC != null ? ', ${_result!.temperatureC!.round()}°C' : ''})' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _result!.source == 'ai' ? 'AI-scored for this specific species' : 'Rule-of-thumb estimate (AI unavailable)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _result!.source == 'ai' ? AppColors.primary : AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 12),
                  WateringResultCard(watering: _result!.watering),
                  const SizedBox(height: 12),
                  FertilizerResultCard(fertilizer: _result!.fertilizer),
                  const SizedBox(height: 12),
                  LightFitResultCard(lightFit: _result!.lightFit),
                ],
              ],
            ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10.5, color: AppColors.textSecondaryOf(context), letterSpacing: 0.4)),
      );
}

