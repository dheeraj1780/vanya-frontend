import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/care_task_tile.dart';
import '../widgets/leaf_burst.dart';
import '../widgets/plan_badge.dart';
import '../widgets/plant_card.dart';
import '../widgets/section_header.dart';

/// Dashboard — "these are your plants and here's what they need." A
/// tab-shell body (see main.dart's _TabShell) — no own Scaffold/AppBar, so
/// this returns pure content, top-padded for the status bar by the shell's
/// SafeArea.
///
/// The plant grid itself now lives on MyPlantsScreen; Home only previews a
/// few plants plus whatever needs attention today, so it stays a quick
/// glance rather than a second copy of the full collection.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// name is null whenever nothing's been captured/set yet (common for
  /// Apple, always true for a never-linked guest — see AppState.userName's
  /// docstring) — falls back to the plain greeting with no name in that
  /// case, exactly the same text this always showed before the feature existed.
  String _greeting(String? name) {
    final hour = DateTime.now().hour;
    final base = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return (name == null || name.isEmpty) ? base : '$base, $name';
  }

  /// Shared by both the plain-list and scroll-box layouts below (E-H003) so
  /// the tile itself — and its "Done" action — is defined in exactly one place.
  Widget _careTaskTileFor(BuildContext context, AppState appState, Plant plant) {
    return CareTaskTile(
      icon: Icons.water_drop_outlined,
      title: 'Water ${plant.nickname}',
      subtitle: plant.nextWateringDue.difference(DateTime.now()).inDays < -1
          ? 'Overdue by ${(-plant.nextWateringDue.difference(DateTime.now()).inHours / 24).ceil()} days'
          : 'Due today',
      urgent: true,
      onTap: () {
        appState.selectedPlantId = plant.id;
        appState.goTo('plantDetail');
      },
      trailing: TextButton(
        onPressed: () {
          appState.handleMarkWatered(plant.id);
          LeafBurst.play(context);
        },
        child: const Text('Done'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final duePlants = appState.plants.where((p) => p.nextWateringDue.difference(DateTime.now()).inHours <= 0).toList()
      ..sort((a, b) => a.nextWateringDue.compareTo(b.nextWateringDue));
    final previewPlants = appState.plants.take(6).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110), // extra bottom padding clears the floating nav
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          // Center, not start: with the badge now on its own line below the
          // greeting, this block is taller than the 40px profile icon —
          // top-aligning them left the icon looking stranded near the top
          // instead of sitting level with the text.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible (loose fit), not Expanded: caps the width so a long
            // name (e.g. "Good morning, Chandrasekaran") can never push the
            // profile icon off the right edge of the screen, but — unlike
            // Expanded — still lets the Column shrink to its actual content
            // width for a short greeting, so the profile icon sits
            // naturally close instead of pinned to the screen edge with a
            // dead gap in between.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ellipsis, not truncated by a neighboring badge anymore
                  // (moved below) — this only ever needs to protect against
                  // the profile icon, so a long name now reads in full far
                  // more often instead of cutting off after a few letters.
                  Text(
                    _greeting(appState.userName),
                    style: AppTypography.h1(AppColors.textOf(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Own line, below the greeting — sharing a line with a
                  // long name was what caused the greeting to get cut off
                  // and, before that, pushed the badge itself off-screen.
                  PlanBadge(planKey: appState.entitlement?.plan ?? (appState.isGuest ? 'guest' : 'plantie'), compact: true),
                  const SizedBox(height: 3),
                  Text(
                    duePlants.isEmpty ? 'Your plants are all set today.' : '${duePlants.length} plant${duePlants.length == 1 ? '' : 's'} need water today',
                    style: AppTypography.body(AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => appState.goTo('settings'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, shape: BoxShape.circle),
                child: Icon(Icons.person_outline, color: AppColors.primaryTintPairOf(context).$2, size: 19),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),

        SectionHeader(title: "Today's care"),
        const SizedBox(height: 12),
        if (duePlants.isEmpty)
          Builder(builder: (context) {
            final (tint, color) = AppColors.primaryTintPairOf(context);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Nothing needs attention right now — nice work.', style: AppTypography.bodyStrong(color))),
                ],
              ),
            );
          })
        else
          // E-H003: this box's height is now *always* fixed the moment
          // there's at least one due plant — not just once there are "too
          // many" to fit. The previous version only capped growth past 3
          // items, so 1-3 due plants still pushed "My plants"/"Quick
          // actions" further down with every plant added — exactly the
          // "Quick actions keeps sliding further down as I add plants"
          // problem, since a freshly-added, never-watered plant is
          // immediately "due" (see Plant.nextWateringDue), so adding
          // plants directly grows this list. Fixed at ~2 tiles tall
          // (scrolls internally for more, same as before) keeps Home's
          // total height constant regardless of plant count.
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: duePlants.length,
              itemBuilder: (context, i) => _careTaskTileFor(context, appState, duePlants[i]),
            ),
          ),

        const SizedBox(height: 26),
        SectionHeader(
          title: 'My plants',
          actionLabel: appState.plants.isEmpty ? null : 'See all',
          onAction: () => appState.goTo('myPlants'),
        ),
        const SizedBox(height: 12),
        if (appState.plants.isEmpty)
          _EmptyPlantsPrompt(onScan: () => appState.goTo('addPlant'))
        else
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: previewPlants.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final plant = previewPlants[i];
                return SizedBox(
                  width: 148,
                  child: PlantCard(
                    plant: plant,
                    onTap: () {
                      appState.selectedPlantId = plant.id;
                      appState.goTo('plantDetail');
                    },
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 26),
        SectionHeader(title: 'Quick actions'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.medical_services_outlined,
                label: 'Diagnose',
                onTap: () {
                  if (appState.plants.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add a plant first, then you can diagnose it.')),
                    );
                    return;
                  }
                  appState.selectedPlantId = appState.plants.first.id;
                  appState.goTo('diagnose', withReturnTo: 'home');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                icon: Icons.calculate_outlined,
                label: 'Calculators',
                onTap: () {
                  appState.selectedPlantId = null; // let CalculatorsScreen default to the first plant
                  appState.goTo('calculators');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 19),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: AppTypography.bodyStrong(AppColors.textOf(context)))),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlantsPrompt extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyPlantsPrompt({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onScan,
      child: Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.placeholderGradientOf(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            const Icon(Icons.center_focus_strong, color: AppColors.primary, size: 26),
            const SizedBox(height: 10),
            Text('No plants yet', style: AppTypography.h3(AppColors.textOf(context))),
            const SizedBox(height: 3),
            Text('Tap to scan your first plant', style: AppTypography.body(AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }
}
