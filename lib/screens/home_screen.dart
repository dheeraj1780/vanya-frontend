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
        // A bounded card, not a bare Row loose in the page's padding — this
        // is the very top of the app, and stacking the greeting, plan
        // badge, status line, and a small round profile icon all directly
        // on the page background (previous layout) gave it no visual edge
        // to read as "the top section" versus everything scrolling below
        // it. A soft surface + border + shadow gives it that boundary, and
        // the avatar now anchors the whole block at a consistent height
        // instead of floating separately at the top-right.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderOf(context)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(
            // start, not center: once the greeting can wrap to 2 lines
            // (below), center-aligning made the avatar drift toward the
            // vertical middle of the whole taller block instead of sitting
            // level with the first line of text, like a name tag reads.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar + plan badge stacked in their own left column, not
              // the avatar alone — with the greeting now up to 2 lines
              // tall, a lone 46px avatar left a noticeably empty gap below
              // it next to the taller text block. Anchoring the badge here
              // fills that gap instead of leaving it bare.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => appState.goTo('settings'),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.primaryTintPairOf(context).$1,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryTintPairOf(context).$2.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Icon(Icons.person_outline, color: AppColors.primaryTintPairOf(context).$2, size: 21),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PlanBadge(planKey: appState.entitlement?.plan ?? (appState.isGuest ? 'guest' : 'plantie'), compact: true),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Expanded, not Flexible — nothing else on this row needs to
              // shrink to content width now, so it can just claim the rest
              // of the card.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // maxLines: 2, not 1 — a 1-line cap on a serif h2 is
                    // what forced "Good morning, Chandrasekaran" down to
                    // "Good morning, Chan..." for any real name longer than
                    // ~10-11 characters. At h2's 19px Fraunces (~10dp/char
                    // for this bold serif), this card's text column is
                    // roughly 340dp - (avatar/badge column width, ~60dp for
                    // the Guest/Plantie/Green Thumb badges, up to ~150dp
                    // for the longer "Photosynthesis PhD" one) - 14dp gap
                    // wide — call it ~34 characters/line, ~68 total, in the
                    // common (short-badge) case. _editName's 40-char cap
                    // (settings_screen.dart) is sized against that: minus
                    // the longest prefix "Good afternoon, " (17 chars),
                    // that's comfortable room for real names to always show
                    // in full. The rare edge case (a maxed-out 40-char name
                    // AND the widest Photosynthesis PhD badge AND a narrow
                    // phone) still degrades gracefully to the ellipsis
                    // below rather than breaking the layout — this is
                    // sized for the common case, not a hard guarantee.
                    Text(
                      _greeting(appState.userName),
                      style: AppTypography.h2(AppColors.textOf(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      duePlants.isEmpty ? 'Your plants are all set today.' : '${duePlants.length} plant${duePlants.length == 1 ? '' : 's'} need water today',
                      style: AppTypography.body(AppColors.textSecondaryOf(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
