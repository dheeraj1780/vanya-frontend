import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/care_guide_section.dart';
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
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plant.nickname, style: AppTypography.h1(AppColors.textOf(context))),
                  if (plant.species != null) ...[
                    const SizedBox(height: 3),
                    Text(plant.species!, style: AppTypography.bodyLarge(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic)),
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
                  if (plant.funFacts.isNotEmpty)
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

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
