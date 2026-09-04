import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../api/client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/leaf_burst.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';

/// "I already know this plant" — the Quick Actions button that skips the
/// camera entirely. Same underlying pipeline as AddPlantScreen
/// (identify -> confirm -> createPlant -> optional photo upload), except
/// the identify step is a text lookup by name (identifyPlantByName) —
/// same ai_actions cost as a photo identify (see the backend's
/// ai_service.identify_plant_by_name), just no image required or sent.
/// A photo is still offered on the result screen, but as an optional
/// finishing touch rather than the thing that drives identification.
class ManualAddScreen extends StatefulWidget {
  const ManualAddScreen({super.key});
  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  String _status = 'idle'; // idle | looking-up | result | saving | error
  String _errorMessage = '';
  IdentifyResult? _result;
  File? _imageFile;
  String? _imageBase64;

  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _handleLookup() async {
    final plantName = _nameController.text.trim();
    if (plantName.isEmpty) return;
    final appState = context.read<AppState>();
    FocusScope.of(context).unfocus();

    setState(() {
      _status = 'looking-up';
      _errorMessage = '';
    });

    try {
      final result = await appState.api.identifyPlantByName(appState.token!, plantName);
      // Same accounting as AddPlantScreen._handleCapture — the lookup call
      // itself is what spent the allowance, whether or not it turned out
      // to genuinely be a plant.
      if (result.usedGardenSetup) {
        final gs = appState.entitlement?.gardenSetup;
        if (gs != null && gs.used == 0) appState.trackEvent('garden_setup_started');
        if (gs != null && gs.remaining == 1) appState.trackEvent('garden_setup_completed');
      } else {
        appState.trackEvent(appState.isGuest ? 'guest_identification_by_name_used' : 'plantie_identification_by_name_used');
      }
      unawaited(appState.refreshEntitlement());

      if (!result.isRealPlant) {
        setState(() => _status = 'idle');
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Hmm, couldn\'t find that one 🌿'),
              content: Text(
                (result.funMessage?.isNotEmpty ?? false)
                    ? result.funMessage!
                    : 'That doesn\'t look like a real plant name — try the common name you know it by.',
              ),
              actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Got it'))],
            ),
          );
        }
        return;
      }

      // Same duplicate-species nudge as AddPlantScreen.
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
              'Is this a different ${result.species}, or the same one?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Same plant')),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('It\'s a different one')),
            ],
          ),
        );
        if (isDifferentPlant != true) {
          setState(() => _status = 'idle');
          return;
        }
      }

      setState(() {
        _status = 'result';
        _result = result;
        _nicknameController.text = result.commonName;
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
        _errorMessage = 'Could not look that up. Try again.';
      });
    }
  }

  Future<void> _handleAddPhoto() async {
    final file = await pickPlantImage(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    setState(() {
      _imageFile = File(file.path);
      _imageBase64 = base64Encode(bytes);
    });
  }

  /// Same shared save path as AddPlantScreen._handleSave — status='active'
  /// costs a garden slot, status='wishlist' a wishlist slot, and the photo
  /// (if the user added one) uploads separately and never blocks the save
  /// on failure.
  Future<void> _handleSave(String status) async {
    final appState = context.read<AppState>();
    final result = _result!;
    final nickname = _nicknameController.text.trim().isEmpty ? result.commonName : _nicknameController.text.trim();
    setState(() => _status = 'saving');

    try {
      final created = await appState.api.createPlant(appState.token!, {
        'nickname': nickname,
        'species': result.species,
        'species_confidence': result.confidence,
        'light_needs': result.lightNeeds,
        'water_frequency_days': result.waterFrequencyDays,
        'fun_facts': result.funFacts,
        'regional_names': result.regionalNames,
        'soil_type': result.soilType.isEmpty ? null : result.soilType,
        'soil_amendments': result.soilAmendments.isEmpty ? null : result.soilAmendments,
        'is_indoor': result.isIndoor,
        'is_pet_safe': result.isPetSafe,
        'is_air_purifying': result.isAirPurifying,
        'care_difficulty': result.careDifficulty,
        'status': status,
      });

      String? photoUrl;
      if (_imageBase64 != null) {
        try {
          photoUrl = await appState.api.uploadPlantPhoto(appState.token!, created['id'], _imageBase64!);
        } catch (e) {
          debugPrint('Photo upload failed (plant was still created): $e');
        }
      }

      final newPlant = Plant(
        id: created['id'],
        status: status,
        nickname: nickname,
        species: result.species,
        speciesConfidence: result.confidence,
        lightNeeds: result.lightNeeds,
        waterFrequencyDays: result.waterFrequencyDays,
        photoUrl: photoUrl,
        funFacts: result.funFacts,
        regionalNames: result.regionalNames,
        soilType: result.soilType.isEmpty ? null : result.soilType,
        soilAmendments: result.soilAmendments.isEmpty ? null : result.soilAmendments,
        isIndoor: result.isIndoor,
        isPetSafe: result.isPetSafe,
        isAirPurifying: result.isAirPurifying,
        careDifficulty: result.careDifficulty,
        createdAt: DateTime.now(),
      );

      if (status == 'wishlist') {
        appState.handleWishlistItemSaved(newPlant);
      } else {
        appState.handlePlantSaved(newPlant);
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
      _nameController.clear();
      _nicknameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.read<AppState>().goBack(fallback: 'home')),
        title: const Text('Add a Plant You Know'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          child: _status == 'result' || _status == 'saving' ? _buildResult(context) : _buildLookup(context),
        ),
      ),
    );
  }

  Widget _buildLookup(BuildContext context) {
    final lookingUp = _status == 'looking-up';
    return Column(
      key: const ValueKey('lookup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Already know what it is? Type its name and skip the photo.', style: AppTypography.body(AppColors.textSecondaryOf(context))),
        const SizedBox(height: 8),
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
                  'We\'ll still look up its watering schedule, light needs, and care facts for you — just from the name, not a photo.',
                  style: AppTypography.caption(AppColors.textSecondaryOf(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('PLANT NAME', style: AppTypography.eyebrow(AppColors.sage)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          enabled: !lookingUp,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Money Plant, Snake Plant, Tulsi'),
          onSubmitted: (_) => _handleLookup(),
          // BUG this fixes (reported: "Look it up" stayed greyed out and
          // did nothing no matter what was typed): the button's onPressed
          // below reads _nameController.text at build time, but nothing
          // was wired to rebuild this screen as that text changed — so it
          // stayed evaluated against the initial empty string forever.
          // Exact same bug as growth_journey_screen.dart's "New growth
          // memory" save button; same fix.
          onChanged: (_) => setState(() {}),
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_errorMessage, style: AppTypography.body(AppColors.accent)),
          ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: lookingUp ? 'Looking it up…' : 'Look it up',
          icon: lookingUp ? null : Icons.search,
          loading: lookingUp,
          onPressed: lookingUp || _nameController.text.trim().isEmpty ? null : _handleLookup,
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
              child: GestureDetector(
                onTap: saving ? null : _handleAddPhoto,
                child: _imageFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_imageFile!, fit: BoxFit.cover),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                              child: const Text('Tap to change', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: AppColors.primaryTintPairOf(context).$1,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 28, color: AppColors.primaryTintPairOf(context).$2),
                              const SizedBox(height: 8),
                              Text('Add a photo (optional)', style: AppTypography.bodyStrong(AppColors.primaryTintPairOf(context).$2)),
                            ],
                          ),
                        ),
                      ),
              ),
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
          // Same fix as AddPlantScreen's own result step, for the same
          // reason: confirms right here that an unfamiliar common_name
          // is genuinely the plant being looked up, before saving it.
          if (result.regionalNames.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('Also known as ${result.regionalNames.join(', ')}', style: AppTypography.body(AppColors.textSecondaryOf(context))),
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
          Text('YOUR NAME FOR IT', style: AppTypography.eyebrow(AppColors.sage)),
          const SizedBox(height: 8),
          TextField(
            controller: _nicknameController,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Fred'),
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
          SecondaryButton(
            label: 'Save to wishlist',
            icon: Icons.bookmark_border,
            onPressed: saving ? null : () => _handleSave('wishlist'),
          ),
          const SizedBox(height: 10),
          if (!saving)
            TextButton(onPressed: _reset, child: const Text('Search again')),
        ],
      ),
    );
  }
}
