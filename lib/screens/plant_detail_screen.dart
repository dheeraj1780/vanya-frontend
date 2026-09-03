import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/care_guide_section.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/leaf_burst.dart';
import '../widgets/plant_image.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';

/// A digital plant profile — hero photo, health/watering/light at a
/// glance, then care actions. Only shows sections backed by real data from
/// the backend (species, light_needs, care_difficulty, water schedule,
/// pet/air-purifying/indoor flags) — no humidity/temperature section,
/// since nothing in the API provides that and fabricating numbers would be
/// worse than omitting the section.
class PlantDetailScreen extends StatefulWidget {
  const PlantDetailScreen({super.key});
  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  DiagnosisResult? _lastDiagnosis;
  bool _removing = false;
  bool _savingNickname = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLastDiagnosis());
  }

  Future<void> _loadLastDiagnosis() async {
    final appState = context.read<AppState>();
    final plant = appState.selectedPlant;
    if (plant == null) return;
    try {
      final result = await appState.api.getLatestDiagnosis(appState.token!, plant.id);
      if (mounted) setState(() => _lastDiagnosis = result);
    } catch (e) {
      debugPrint('Failed to check for a stored diagnosis: $e');
    }
  }

  /// Renaming a plant — was referenced in the test plan but never actually
  /// built: nickname is set once at scan time (always the AI's common
  /// name, e.g. "Golden Pothos") and shown here as a plain, non-editable
  /// Text. The backend has always fully supported this (PlantUpdateInput.
  /// nickname -> PUT /plants/{id}, and ApiClient.updatePlant already
  /// exists) — the whole gap was just this screen never offering a way to
  /// call it. Unlike the account display name, an empty nickname isn't
  /// allowed: this is the plant's only name everywhere else in the app
  /// (Home, My Plants, Reminders), so leaving it blank would break those,
  /// not just look empty.
  Future<void> _editNickname(Plant plant) async {
    final appState = context.read<AppState>();
    final controller = TextEditingController(text: plant.nickname);
    final newNickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Rename plant'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 50,
            decoration: const InputDecoration(hintText: 'e.g. Baby Fern'),
            onChanged: (_) => setDialogState(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (newNickname == null || newNickname == plant.nickname || !mounted) return;

    setState(() => _savingNickname = true);
    try {
      final updated = await appState.api.updatePlant(appState.token!, plant.id, {'nickname': newNickname});
      appState.updatePlantLocally(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not rename this plant. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  /// Was only ever set once, at scan/lookup time (reusing the identify
  /// photo, or whatever was optionally added on the manual-add result
  /// screen) — no way to add one later, or replace a bad shot, once the
  /// plant already existed. uploadPlantPhoto itself already existed and
  /// was already used at creation time; this is just the missing second
  /// entry point into it.
  Future<void> _handleChangePhoto(Plant plant) async {
    final appState = context.read<AppState>();
    final file = await pickPlantImage(context);
    if (file == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await File(file.path).readAsBytes();
      final photoUrl = await appState.api.uploadPlantPhoto(appState.token!, plant.id, base64Encode(bytes));
      appState.updatePlantLocally(plant.copyWith(photoUrl: photoUrl));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the photo. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _confirmDelete(Plant plant) async {
    final appState = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${plant.nickname}?'),
        content: const Text('This also deletes its diagnosis history. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removing = true);
    try {
      await appState.handleDeletePlant(plant.id); // navigates to myPlants on success
    } on ApiException catch (err) {
      if (mounted) {
        setState(() => _removing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _removing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove this plant. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final plant = appState.selectedPlant;
    if (plant == null) return const SizedBox.shrink();

    final daysUntilWater = plant.nextWateringDue.difference(DateTime.now()).inHours / 24;
    final needsWater = daysUntilWater <= 0;

    return Scaffold(
      backgroundColor: AppColors.bgOf(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.bgOf(context),
            surfaceTintColor: Colors.transparent,
            leading: _CircleIconButton(icon: Icons.arrow_back, onTap: () => appState.goBack(fallback: 'home')),
            actions: [
              _CircleIconButton(
                icon: Icons.camera_alt_outlined,
                loading: _uploadingPhoto,
                onTap: () => _handleChangePhoto(plant),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: GestureDetector(
                // Tap the hero photo to view it full-screen over a blurred
                // backdrop of this same page — popping the viewer just
                // reveals this screen again exactly as it was, since it's
                // still underneath (opaque: false), not rebuilt.
                onTap: () => Navigator.of(context).push(_FullScreenPlantImageRoute(imageUrl: plant.photoUrl)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlantImage(url: plant.photoUrl, borderRadius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black38],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _savingNickname ? null : () => _editNickname(plant),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(child: Text(plant.nickname, style: AppTypography.h1(AppColors.textOf(context)))),
                        const SizedBox(width: 8),
                        _savingNickname
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondaryOf(context)),
                      ],
                    ),
                  ),
                  if (plant.species != null) ...[
                    const SizedBox(height: 3),
                    Text(plant.species!, style: AppTypography.bodyLarge(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic)),
                  ],
                  // E-MP001: the botanical name alone doesn't mean much to
                  // most people — surface the household/vernacular names
                  // (often Indian ones — see ai_provider.IDENTIFY_PROMPT)
                  // right here too, not just buried in the Facts screen.
                  if (plant.regionalNames.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Also known as ${plant.regionalNames.join(', ')}',
                      style: AppTypography.body(AppColors.textSecondaryOf(context)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusBadge(label: needsWater ? 'Needs water' : 'Healthy', tone: needsWater ? StatusTone.attention : StatusTone.healthy, icon: Icons.eco_outlined),
                      if (plant.isPetSafe == true) const StatusBadge(label: 'Pet safe', icon: Icons.pets_outlined),
                      if (plant.isAirPurifying == true) const StatusBadge(label: 'Air purifying', icon: Icons.air_outlined),
                      if (plant.careDifficulty != null) StatusBadge(label: '${plant.careDifficulty} care'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.water_drop_outlined,
                          label: 'Watering',
                          value: 'Every ${plant.waterFrequencyDays}d',
                          detail: needsWater ? 'Due now' : 'Next in ${daysUntilWater.ceil()}d',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.wb_sunny_outlined,
                          label: 'Light',
                          value: plant.lightNeeds ?? 'Unknown',
                          detail: null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  PrimaryButton(
                    label: 'Mark watered',
                    icon: Icons.check,
                    onPressed: () {
                      appState.handleMarkWatered(plant.id);
                      LeafBurst.play(context);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_lastDiagnosis != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SecondaryButton(
                        label: 'View last diagnosis',
                        icon: Icons.history,
                        onPressed: () {
                          appState.diagnosisResult = _lastDiagnosis;
                          appState.goTo('diagnosisResult', withReturnTo: 'plantDetail');
                        },
                      ),
                    ),
                  SecondaryButton(
                    label: _lastDiagnosis != null ? 'Diagnose again' : 'Diagnose a problem',
                    icon: Icons.medical_services_outlined,
                    onPressed: () => appState.goTo('diagnose', withReturnTo: 'plantDetail'),
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: 'Growth Journey',
                    icon: Icons.eco_outlined,
                    onPressed: () {
                      appState.growthJourneyPlantId = plant.id;
                      appState.goTo('growthJourney', withReturnTo: 'plantDetail');
                    },
                  ),
                  if (plant.funFacts.isNotEmpty || plant.regionalNames.isNotEmpty || (plant.soilType?.isNotEmpty ?? false))
                    Center(
                      child: TextButton.icon(
                        onPressed: () => appState.goTo('plantFacts'),
                        icon: const Icon(Icons.auto_awesome, size: 14),
                        label: const Text('Plant facts'),
                      ),
                    ),

                  const SizedBox(height: 8),
                  CareGuideSection(plant: plant),

                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _removing ? null : () => _confirmDelete(plant),
                      icon: _removing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                          : const Icon(Icons.delete_outline, size: 15, color: AppColors.accent),
                      label: Text(_removing ? 'Removing…' : 'Remove plant', style: const TextStyle(color: AppColors.accent)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  const _InfoTile({required this.icon, required this.label, required this.value, this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.borderOf(context))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(label.toUpperCase(), style: AppTypography.caption(AppColors.textSecondaryOf(context))),
          const SizedBox(height: 3),
          Text(value, style: AppTypography.h3(AppColors.textOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (detail != null) Text(detail!, style: AppTypography.body(AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

/// Pushed over the current screen (opaque: false) rather than replacing
/// it — Plant Detail stays alive and rendered underneath, so a) it's
/// there to blur, and b) popping this reveals it exactly as it was, no
/// rebuild/scroll-reset. See PlantDetailScreen's hero photo onTap.
class _FullScreenPlantImageRoute extends PageRouteBuilder<void> {
  _FullScreenPlantImageRoute({required String? imageUrl})
      : super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
            opacity: animation,
            child: _FullScreenPlantImage(imageUrl: imageUrl),
          ),
        );
}

class _FullScreenPlantImage extends StatelessWidget {
  final String? imageUrl;
  const _FullScreenPlantImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurs whatever's actually behind — the real Plant Detail
          // screen, still painted underneath this route — not a copy.
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            // Swallows taps on the image itself so only tapping the
            // blurred surround dismisses it — matches the common
            // photo-viewer convention (tap image to zoom/no-op, tap
            // outside to close) rather than a hair-trigger dismiss.
            child: GestureDetector(
              onTap: () {},
              child: PlantImage(url: imageUrl, borderRadius: AppRadius.lg, fit: BoxFit.contain),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: _CircleIconButton(icon: Icons.close, onTap: () => Navigator.of(context).pop()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  const _CircleIconButton({required this.icon, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
