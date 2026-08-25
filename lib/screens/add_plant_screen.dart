import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../api/client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/leaf_burst.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';

/// Scan — capture/pick a photo, identify it, then show a result card the
/// user explicitly confirms before it's saved (a discovery moment, not an
/// instant silent save). The underlying calls are unchanged
/// (identifyPlant → createPlant → uploadPlantPhoto); only *when* the
/// create+upload pair fires moved from "immediately" to "on Add tap".
class AddPlantScreen extends StatefulWidget {
  const AddPlantScreen({super.key});
  @override
  State<AddPlantScreen> createState() => _AddPlantScreenState();
}

class _AddPlantScreenState extends State<AddPlantScreen> {
  String _status = 'idle'; // idle | identifying | result | saving | error
  String _errorMessage = '';
  IdentifyResult? _result;
  File? _imageFile;
  String? _imageBase64;

  Future<void> _handleCapture() async {
    final appState = context.read<AppState>();
    // Tier-aware pre-check (proactive UX only — the real, secure check
    // happens server-side in check_plant_slot_limit regardless). Falls
    // back to blocking at 3 if entitlement hasn't loaded yet rather than
    // letting an unbounded number of plants through.
    final plantLimit = appState.entitlement?.plantLimit ?? 3;
    if (appState.plants.length >= plantLimit) {
      if (appState.isGuest) {
        appState.guestGateReason = "You've discovered $plantLimit plants with VANYA. Sign in to become a Plantie and keep growing your garden.";
        appState.goTo('guestGate', withReturnTo: 'home');
      } else {
        appState.trackEvent('plant_limit_reached');
        appState.goTo('paywall', withReturnTo: 'home');
      }
      return;
    }

    final source = await showImageSourceSheet(context);
    if (source == null) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
    if (file == null) return;

    setState(() {
      _status = 'identifying';
      _errorMessage = '';
      _imageFile = File(file.path);
    });

    try {
      final bytes = await _imageFile!.readAsBytes();
      final imageBase64 = base64Encode(bytes);
      final result = await appState.api.identifyPlant(appState.token!, imageBase64);
      // "used" events fire on the identify call itself (the action that
      // actually consumes the allowance), not on save — matches what the
      // backend counts against the weekly/lifetime limit, and applies
      // whether or not it turned out to be a real plant (the AI call, and
      // whatever it costs, already happened either way). appState.entitlement
      // here is still the *pre*-call snapshot (refreshEntitlement runs
      // after), so its garden_setup numbers describe what was true going
      // into this specific call.
      if (result.usedGardenSetup) {
        final gs = appState.entitlement?.gardenSetup;
        if (gs != null && gs.used == 0) appState.trackEvent('garden_setup_started');
        if (gs != null && gs.remaining == 1) appState.trackEvent('garden_setup_completed');
      } else {
        appState.trackEvent(appState.isGuest ? 'guest_identification_used' : 'plantie_identification_used');
      }
      unawaited(appState.refreshEntitlement());

      // BUG-C003: the old prompt forced a confident species guess out of
      // every image, including artificial plants and random objects —
      // Gemini itself now judges whether this is a real, living plant.
      // False here means it isn't, so this doesn't become a save-able
      // result at all — a playful pop-up instead, then straight back to
      // capture so the user can try an actual plant.
      if (!result.isRealPlant) {
        setState(() {
          _status = 'idle';
          _imageFile = null;
        });
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Hmm, not quite a plant 🌿'),
              content: Text(
                (result.funMessage?.isNotEmpty ?? false)
                    ? result.funMessage!
                    : 'That doesn\'t look like a real, living plant — try snapping an actual one!',
              ),
              actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Got it'))],
            ),
          );
        }
        return;
      }

      // Catches the "scanned the same physical plant twice, thought it was
      // a new one" case (e.g. two money plants — the second scan matches
      // the first's species) without blocking anyone who genuinely owns
      // more than one of the same species: ask, rather than assume either
      // way, before this becomes a save-able result.
      Plant? existingMatch;
      for (final p in appState.plants) {
        if (p.species != null && p.species!.trim().toLowerCase() == result.species.trim().toLowerCase()) {
          existingMatch = p;
          break;
        }
      }
      if (existingMatch != null && mounted) {
        final isDifferentPlant = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Already in your garden?'),
            content: Text(
              'You already have a ${existingMatch!.nickname} (${result.species}) in your garden. '
              'Is this a different ${result.species}, or did you scan that same plant again?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Same plant')),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('It\'s a different one')),
            ],
          ),
        );
        if (isDifferentPlant != true) {
          setState(() {
            _status = 'idle';
            _imageFile = null;
          });
          return;
        }
      }

      setState(() {
        _status = 'result';
        _result = result;
        _imageBase64 = imageBase64;
      });
    } on ApiException catch (err) {
      setState(() => _status = 'error');
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('identification_limit_reached');
        appState.goTo('paywall', withReturnTo: 'home');
      } else if (err.errorCode == 'GUEST_SIGNIN_REQUIRED') {
        appState.trackEvent('identification_limit_reached');
        appState.guestGateReason = err.message;
        appState.goTo('guestGate', withReturnTo: 'home');
      } else {
        setState(() => _errorMessage = err.message);
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Could not identify this plant. Try again.';
      });
    }
  }

  /// Shared by both save destinations — status='active' costs a garden
  /// slot (check_plant_limit), status='wishlist' costs a wishlist slot
  /// instead (check_wishlist_limit). Either way the identification that
  /// produced this result already spent its allowance use back in
  /// _handleCapture; this step is a pure data-write, not a second AI call.
  Future<void> _handleSave(String status) async {
    final appState = context.read<AppState>();
    final result = _result!;
    final imageBase64 = _imageBase64!;
    setState(() => _status = 'saving');

    try {
      final created = await appState.api.createPlant(appState.token!, {
        'nickname': result.commonName,
        'species': result.species,
        'species_confidence': result.confidence,
        'light_needs': result.lightNeeds,
        'water_frequency_days': result.waterFrequencyDays,
        'fun_facts': result.funFacts,
        'regional_names': result.regionalNames,
        'soil_type': result.soilType.isEmpty ? null : result.soilType,
        'is_indoor': result.isIndoor,
        'is_pet_safe': result.isPetSafe,
        'is_air_purifying': result.isAirPurifying,
        'care_difficulty': result.careDifficulty,
        'status': status,
      });

      // Reuse the identify photo as the plant's profile photo — same
      // reasoning as the React version: asking for a second photo here
      // would be redundant friction for no benefit.
      String? photoUrl;
      try {
        photoUrl = await appState.api.uploadPlantPhoto(appState.token!, created['id'], imageBase64);
      } catch (e) {
        debugPrint('Photo upload failed (plant was still created): $e');
      }

      final newPlant = Plant(
        id: created['id'],
        status: status,
        nickname: result.commonName,
        species: result.species,
        speciesConfidence: result.confidence,
        lightNeeds: result.lightNeeds,
        waterFrequencyDays: result.waterFrequencyDays,
        photoUrl: photoUrl,
        funFacts: result.funFacts,
        isIndoor: result.isIndoor,
        isPetSafe: result.isPetSafe,
        isAirPurifying: result.isAirPurifying,
        careDifficulty: result.careDifficulty,
        createdAt: DateTime.now(),
      );

      if (status == 'wishlist') {
        appState.handleWishlistItemSaved(newPlant); // navigates to myPlants itself
      } else {
        appState.handlePlantSaved(newPlant); // navigates to home itself
      }
    } on ApiException catch (err) {
      setState(() => _status = 'result');
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('plant_limit_reached');
        appState.goTo('paywall', withReturnTo: 'home');
      } else if (err.errorCode == 'GUEST_SIGNIN_REQUIRED') {
        appState.guestGateReason = err.message;
        appState.goTo('guestGate', withReturnTo: 'home');
      } else {
        setState(() => _errorMessage = err.message);
      }
    } catch (e) {
      setState(() {
        _status = 'result';
        _errorMessage = 'Could not save this plant. Try again.';
      });
    }
  }

  void _reset() {
    setState(() {
      _status = 'idle';
      _result = null;
      _imageFile = null;
      _imageBase64 = null;
      _errorMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.read<AppState>().goBack(fallback: 'home')),
        title: const Text('Scan Plant'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          child: _status == 'result' || _status == 'saving' ? _buildResult(context) : _buildCapture(context),
        ),
      ),
    );
  }

  Widget _buildCapture(BuildContext context) {
    final identifying = _status == 'identifying';
    return Column(
      key: const ValueKey('capture'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Take a clear photo of the whole plant in daylight.', style: AppTypography.body(AppColors.textSecondaryOf(context))),
        const SizedBox(height: 8),
        // Sets expectations up front instead of only reacting after the
        // fact (see BUG-C003's fun_message pop-up) — the standard pattern
        // for camera-capture flows: a small, calm hint near the viewfinder,
        // not a blocking dialog every time.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.sageTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.sage),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Works best on real, living plants — toys, photos, and artificial plants can\'t be identified.',
                  style: AppTypography.caption(AppColors.textSecondaryOf(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.placeholderGradientOf(context),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.18), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: _imageFile != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_imageFile!, fit: BoxFit.cover),
                      Container(color: Colors.black38),
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ],
                  )
                // BUG-D001: this circle + label looked exactly like a
                // button (big icon, bold colored call-to-action text) but
                // had no onTap at all — only the separate "Scan Plant"
                // button further down actually worked, so tapping the
                // obvious-looking target here did nothing. Now it's the
                // same action as that button, and the label no longer
                // claims the real control is somewhere else.
                : InkWell(
                    onTap: identifying ? null : _handleCapture,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.center_focus_strong, size: 32, color: AppColors.primary),
                          ),
                          const SizedBox(height: 16),
                          Text(identifying ? 'Identifying…' : 'Tap to scan', style: AppTypography.bodyStrong(AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_errorMessage, style: AppTypography.body(AppColors.accent)),
          ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: identifying ? 'Identifying…' : 'Scan Plant',
          icon: identifying ? null : Icons.center_focus_strong,
          loading: identifying,
          onPressed: identifying ? null : _handleCapture,
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    final saving = _status == 'saving';
    return SingleChildScrollView(
      key: const ValueKey('result'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: AspectRatio(
              aspectRatio: 1.2,
              child: _imageFile != null ? Image.file(_imageFile!, fit: BoxFit.cover) : Container(color: AppColors.primaryTintPairOf(context).$1),
            ),
          ),
          const SizedBox(height: 18),
          Text('PLANT IDENTIFIED', style: AppTypography.eyebrow(AppColors.sage)),
          const SizedBox(height: 4),
          Text(result.commonName, style: AppTypography.h1(AppColors.textOf(context))),
          if (result.species.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(result.species, style: AppTypography.body(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(label: '${result.confidence} confidence', tone: StatusTone.healthy, icon: Icons.verified_outlined),
              if (result.usedGardenSetup)
                const StatusBadge(label: 'Garden setup ✨', tone: StatusTone.neutral, icon: Icons.auto_awesome),
            ],
          ),
          const SizedBox(height: 16),
          if (result.careNote.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.borderOf(context))),
              child: Text(result.careNote, style: AppTypography.bodyLarge(AppColors.textOf(context))),
            ),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_errorMessage, style: AppTypography.body(AppColors.accent)),
            ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: saving ? 'Adding…' : 'Add to My Plants',
            loading: saving,
            onPressed: saving
                ? null
                : () {
                    LeafBurst.play(context);
                    _handleSave('active');
                  },
          ),
          const SizedBox(height: 10),
          // Not ready to commit a garden slot yet? Save it for later
          // instead — doesn't count against the (smaller) plant limit, see
          // MyPlantsScreen's Wishlist tab.
          SecondaryButton(
            label: 'Save to wishlist',
            icon: Icons.bookmark_border,
            onPressed: saving ? null : () => _handleSave('wishlist'),
          ),
          const SizedBox(height: 10),
          if (!saving)
            TextButton(onPressed: _reset, child: const Text('Scan again')),
        ],
      ),
    );
  }
}
