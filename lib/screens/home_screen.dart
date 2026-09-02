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

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /// Replaces the old "X plant(s) need water today" line under the
  /// greeting — that duplicated the Today's care section immediately
  /// below it word-for-word. The date is real, non-redundant context
  /// instead, the same "quiet second line under a greeting" pattern most
  /// habit/health apps use.
  String _today() {
    final now = DateTime.now();
    return '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';
  }

  /// Shared by both the plain-list and scroll-box layouts below (E-H003) so
  /// the tile itself — and its "Done" action — is defined in exactly one place.
  Widget _careTaskTileFor(BuildContext context, AppState appState, Plant plant) {
    final hoursUntil = plant.nextWateringDue.difference(DateTime.now()).inHours;
    return CareTaskTile(
      icon: Icons.water_drop_outlined,
      title: 'Water ${plant.nickname}',
      // hoursUntil <= 0 covers "overdue by less than a day" too (previously
      // only `inDays < -1` counted as overdue, so a plant a few hours past
      // due wrongly still read "Due today" instead of "Overdue").
      subtitle: hoursUntil <= 0
          ? (hoursUntil <= -24 ? 'Overdue by ${(-hoursUntil / 24).ceil()} days' : 'Overdue')
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
    // BUG FIX: this used to only be `inHours <= 0` (already overdue), while
    // PlantCard's own "Water today" badge and RemindersScreen's "Due today"
    // label both use `< 24 hours away` (days < 1) — so a plant due later
    // TODAY (say, 6pm, checked at 10am) showed "Water today" right on its
    // own card but never appeared in this "needs water today" list at all.
    // Matched to the same < 24h threshold everywhere so a plant that says
    // "due today" anywhere in the app always shows up here too.
    final duePlants = appState.plants.where((p) => p.nextWateringDue.difference(DateTime.now()).inHours < 24).toList()
      ..sort((a, b) => a.nextWateringDue.compareTo(b.nextWateringDue));
    final previewPlants = appState.plants.take(6).toList();

    return ListView(
      // Was 110 — CustomBottomNav's actual reserved height is 68 (pill) +
      // 34 (raised Scan circle) + 14 (its own bottom padding) = 116, so
      // even fully scrolled to the end this never actually cleared it;
      // the last row of Quick Actions sat permanently behind the nav.
      // 140 gives real clearance past that 116, not just barely matching it.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      children: [
        // Redesigned for a minimal, editorial feel — the previous version
        // boxed the greeting in a bordered/shadowed card, which was the
        // single biggest thing making the top of the page look heavy: a
        // card whose only job is to hold a hello reads as one more UI
        // element competing for attention, not a calm opener. Dropped
        // entirely — the greeting now sits directly on the page's own
        // warm background, the same way a masthead or a letter's
        // salutation would, and lets Today's care right below it be the
        // first actual "card" the eye lands on.
        // No avatar here anymore — a person-icon-in-a-circle is a near-
        // universal "tap for your account" affordance, and it wasn't one:
        // once Profile got its own proper tab on the bottom nav, this icon
        // did nothing when tapped, which is worse than not being there at
        // all — an element that *looks* interactive but isn't teaches
        // people to distrust every tappable-looking thing in the app. It
        // was never showing a real photo either (just a generic
        // placeholder), so removing it loses nothing and the greeting gets
        // the header's full width to itself.
        //
        // maxLines: 2, not 1 — a 1-line cap on a serif h1 is what forced
        // "Good morning, Chandrasekaran" down to "Good morning, Chan..."
        // for any real name longer than ~14 characters. _editName's
        // 40-char cap (settings_screen.dart) still degrades to the
        // ellipsis below for the rare maxed-out name on a narrow phone —
        // sized for the common case, not a hard guarantee.
        Text(
          _greeting(appState.userName),
          style: AppTypography.h1(AppColors.textOf(context)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // Plan badge + today's date, both quiet secondary-line info —
        // replaces the old "X plant(s) need water today" line, which just
        // repeated the Today's care section word-for-word one glance below it.
        // mainAxisSize.min, and the date is no longer wrapped in Expanded —
        // an Expanded Text stretched this row's hit-testable/visual claim
        // across the full page width even though "Thursday, 3 September"
        // is short, leaving a long stretch of unused space on the right
        // that read like something was missing there. Sitting at its
        // natural content width instead matches how the greeting above it
        // already behaves.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlanBadge(planKey: appState.entitlement?.plan ?? (appState.isGuest ? 'guest' : 'plantie'), compact: true),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _today(),
                style: AppTypography.body(AppColors.textSecondaryOf(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

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
        if (appState.plants.isEmpty && !appState.hasLoadedPlantsOnce && appState.plantsLoadError.isEmpty)
          // Still loading (or retrying) the very first fetch — NOT "no
          // plants yet". A cold backend can genuinely take a while (see
          // AppState.refreshPlants' doc); showing the same empty-garden
          // prompt here is what taught people to force-close and reopen
          // instead of just waiting a moment longer.
          const _PlantsLoadingPrompt()
        else if (appState.plants.isEmpty && appState.plantsLoadError.isNotEmpty)
          _PlantsErrorPrompt(message: appState.plantsLoadError, onRetry: () => appState.refreshPlants())
        else if (appState.plants.isEmpty)
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

/// Was a horizontal icon+label bar in a bordered white box, matching the
/// header/care-tile treatment being replaced elsewhere on this screen —
/// vertical (icon over label) on a flat sage-tinted surface instead reads
/// as a quiet app-tile rather than a form row, and drops one more hard
/// border from the page.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (tint, color) = AppColors.sageTintPairOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(label, style: AppTypography.bodyStrong(AppColors.textOf(context))),
          ],
        ),
      ),
    );
  }
}

/// Shown while the very first plants fetch is still in flight (or being
/// retried — see AppState.refreshPlants) — same footprint as
/// _EmptyPlantsPrompt so nothing jumps around once real data or the empty
/// state replaces it, but visually distinct (spinner, no "tap to scan"
/// call to action) so it doesn't read as "you have no plants".
///
/// Back to a plain StatelessWidget — the delayed "Waking up the server…"
/// swap was specific to the free-tier Render backend's cold-start
/// behavior (moving off that before production), so that messaging no
/// longer applies. AppState.refreshPlants' own timeout/retry logic is
/// untouched — this is still real defense against an ordinary slow or
/// flaky connection, just without cold-start-specific copy.
class _PlantsLoadingPrompt extends StatelessWidget {
  const _PlantsLoadingPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
          const SizedBox(height: 12),
          Text('Loading your garden…', style: AppTypography.body(AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

/// The first fetch genuinely failed (all of refreshPlants' retries used
/// up) — was previously indistinguishable from "you have zero plants",
/// which is what taught people to force-close and reopen the whole app
/// instead of just tapping to try again.
class _PlantsErrorPrompt extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _PlantsErrorPrompt({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.accentTintPairOf(context).$1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, color: AppColors.accentTintPairOf(context).$2, size: 24),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: AppTypography.body(AppColors.textOf(context))),
            const SizedBox(height: 8),
            Text('Tap to retry', style: AppTypography.bodyStrong(AppColors.accentTintPairOf(context).$2)),
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
