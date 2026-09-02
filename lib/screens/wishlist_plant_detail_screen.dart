import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/plant_image.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';

/// A wishlist plant's "individual view" — species info + care preview,
/// with Growth Journey and Add to Garden living here instead of as
/// cramped icons on the wishlist grid card (see WishlistCard, which now
/// just opens this). Deliberately lighter than PlantDetailScreen: no
/// watering status/Mark watered/Diagnose, since a wishlist plant isn't
/// actually being cared for yet — this is a "should I adopt this plant"
/// view, not a care dashboard.
class WishlistPlantDetailScreen extends StatefulWidget {
  const WishlistPlantDetailScreen({super.key});
  @override
  State<WishlistPlantDetailScreen> createState() => _WishlistPlantDetailScreenState();
}

class _WishlistPlantDetailScreenState extends State<WishlistPlantDetailScreen> {
  bool _moving = false;

  Future<void> _handleMoveToGarden(AppState appState, String plantId) async {
    setState(() => _moving = true);
    try {
      await appState.handleMoveToGarden(plantId);
      if (mounted) appState.goBack(fallback: 'myPlants');
    } catch (e) {
      if (mounted) {
        setState(() => _moving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not move this plant to your garden. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // growthJourneyPlantId doubles as "which wishlist plant is open" here
    // — same field Growth Journey itself reads (see AppState's own doc),
    // reused rather than adding a second nearly-identical id field.
    final plant = appState.growthJourneyPlant;
    if (plant == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.bgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.bgOf(context),
        surfaceTintColor: Colors.transparent,
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'myPlants')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(aspectRatio: 1.15, child: PlantImage(url: plant.photoUrl, borderRadius: 0)),
            ),
            const SizedBox(height: 18),
            Text(plant.nickname, style: AppTypography.h1(AppColors.textOf(context))),
            if (plant.species != null) ...[
              const SizedBox(height: 3),
              Text(plant.species!, style: AppTypography.bodyLarge(AppColors.textSecondaryOf(context)).copyWith(fontStyle: FontStyle.italic)),
            ],
            if (plant.regionalNames.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('Also known as ${plant.regionalNames.join(', ')}', style: AppTypography.body(AppColors.textSecondaryOf(context))),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (plant.isPetSafe == true) const StatusBadge(label: 'Pet safe', icon: Icons.pets_outlined),
                if (plant.isAirPurifying == true) const StatusBadge(label: 'Air purifying', icon: Icons.air_outlined),
                if (plant.careDifficulty != null) StatusBadge(label: '${plant.careDifficulty} care'),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _InfoTile(icon: Icons.water_drop_outlined, label: 'Watering', value: 'Every ${plant.waterFrequencyDays}d'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoTile(icon: Icons.wb_sunny_outlined, label: 'Light', value: plant.lightNeeds ?? 'Unknown'),
                ),
              ],
            ),
            // No Growth Journey entry here — this screen's own docstring
            // already draws the line: a wishlist plant "isn't actually
            // being cared for yet... not a care dashboard." Growth Journey
            // is dated photo memories tracking a plant's care over time;
            // there's no journey to document for something that isn't
            // being grown yet. It's still reachable normally once the
            // plant is actually moved into the garden.
            if (plant.funFacts.isNotEmpty) ...[
              const SizedBox(height: 24),
              // No "About your X" framing here on purpose — this is a
              // plant the user doesn't own yet, so a plain "Fun facts"
              // label (same as "Also known as" above it) avoids implying
              // possession the way PlantFactsScreen's title correctly
              // does for an owned plant.
              Text('FUN FACTS', style: AppTypography.caption(AppColors.textSecondaryOf(context)).copyWith(letterSpacing: 0.4)),
              const SizedBox(height: 8),
              for (final fact in plant.funFacts)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome, size: 15, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(fact, style: AppTypography.body(AppColors.textOf(context)).copyWith(height: 1.5))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      // Pinned bar, not just another button in the scroll content — this
      // is the one action the whole screen exists to lead someone to, so
      // it stays reachable (and visually dominant) regardless of scroll
      // position, the way a checkout/adopt CTA normally would.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: PrimaryButton(
            label: _moving ? 'Moving…' : 'Add to garden',
            icon: Icons.eco,
            loading: _moving,
            onPressed: _moving ? null : () => _handleMoveToGarden(appState, plant.id),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

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
        ],
      ),
    );
  }
}
