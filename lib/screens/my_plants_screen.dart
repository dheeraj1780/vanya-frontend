import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/plant_card.dart';
import '../widgets/section_header.dart';
import '../widgets/wishlist_card.dart';
import 'filters_screen.dart';

/// The full plant collection — split out from Home (which used to carry
/// both the dashboard AND the grid) so Home can stay a lightweight "what
/// needs attention today" summary while this screen is the browsable,
/// filterable collection. A tab-shell body (see main.dart's _TabShell) — no
/// own Scaffold/AppBar.
///
/// Now two tabs in one screen: "My Garden" (active plants, counts against
/// plantLimit, unchanged from before) and "Wishlist" (plants identified but
/// not yet given a garden slot — see plans.py's WISHLIST note on why this
/// exists: a hard plant cap shouldn't also cap curiosity).
class MyPlantsScreen extends StatefulWidget {
  const MyPlantsScreen({super.key});
  @override
  State<MyPlantsScreen> createState() => _MyPlantsScreenState();
}

class _MyPlantsScreenState extends State<MyPlantsScreen> {
  bool _wishlistLoaded = false;
  String? _movingPlantId;

  // Read/written through AppState.myPlantsShowWishlist (not local State) —
  // see that field's own docstring for why: this screen gets torn down and
  // rebuilt from scratch on every visit, so anything kept purely here forgot
  // which tab was open the moment you navigated away and back.
  bool get _showWishlist => context.read<AppState>().myPlantsShowWishlist;

  @override
  void initState() {
    super.initState();
    // Coming back to an already-remembered Wishlist tab (rather than
    // switching to it just now via _switchTab) still needs its own load —
    // this screen is a fresh State every visit, so _wishlistLoaded starts
    // false regardless of which tab AppState remembers being open.
    if (_showWishlist) {
      _wishlistLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().refreshWishlist();
      });
    }
  }

  void _switchTab(bool wishlist) {
    final appState = context.read<AppState>();
    setState(() => appState.myPlantsShowWishlist = wishlist);
    if (wishlist && !_wishlistLoaded) {
      _wishlistLoaded = true;
      appState.refreshWishlist();
    }
  }

  Future<void> _handleMoveToGarden(AppState appState, String plantId) async {
    setState(() => _movingPlantId = plantId);
    try {
      await appState.handleMoveToGarden(plantId);
    } on ApiException catch (err) {
      setState(() => _movingPlantId = null);
      if (!mounted) return;
      if (err.errorCode == 'PLAN_LIMIT_EXCEEDED') {
        appState.trackEvent('plant_limit_reached');
        appState.goTo('paywall', withReturnTo: 'myPlants');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      }
      return;
    }
    if (mounted) setState(() => _movingPlantId = null);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activeList = appState.plants;
    final wishlistList = appState.wishlist;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: _showWishlist ? 'Wishlist' : 'My plants',
            trailing: Row(
              children: [
                if (!_showWishlist)
                  Builder(builder: (context) {
                    final (tint, tintFg) = AppColors.primaryTintPairOf(context);
                    return GestureDetector(
                      onTap: () => showFiltersSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: appState.hasActiveFilters ? tint : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: appState.hasActiveFilters ? tintFg : AppColors.borderOf(context)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune, size: 14, color: appState.hasActiveFilters ? tintFg : AppColors.textSecondaryOf(context)),
                            const SizedBox(width: 4),
                            Text(
                              appState.hasActiveFilters ? 'Filtered' : 'Filter',
                              style: AppTypography.caption(appState.hasActiveFilters ? tintFg : AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => appState.goTo('addPlant'),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GardenWishlistToggle(
            showWishlist: _showWishlist,
            wishlistCount: appState.entitlement?.wishlist.count ?? wishlistList.length,
            onChanged: _switchTab,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _showWishlist
                ? (wishlistList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 80),
                          child: Text(
                            'Spotted a plant you like? Identify it and save it here — no garden slot needed until you\'re ready.',
                            textAlign: TextAlign.center,
                            style: AppTypography.body(AppColors.textSecondaryOf(context)),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: wishlistList.length,
                        itemBuilder: (context, i) {
                          final plant = wishlistList[i];
                          return WishlistCard(
                            plant: plant,
                            moving: _movingPlantId == plant.id,
                            onMoveToGarden: () => _handleMoveToGarden(appState, plant.id),
                            onRemove: () => appState.handleRemoveFromWishlist(plant.id),
                            onTap: () {
                              appState.growthJourneyPlantId = plant.id;
                              appState.goTo('wishlistPlantDetail', withReturnTo: 'myPlants');
                            },
                          );
                        },
                      ))
                : (activeList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 80),
                          child: !appState.hasLoadedPlantsOnce && appState.plantsLoadError.isEmpty
                              // Still loading the first fetch, not actually
                              // empty — same distinction Home makes (see
                              // AppState.refreshPlants' doc); this screen
                              // used to show the exact same "no plants
                              // yet" text either way.
                              ? const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
                                    SizedBox(height: 10),
                                    Text('Loading your garden…'),
                                  ],
                                )
                              : appState.plantsLoadError.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => appState.refreshPlants(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.cloud_off_outlined, color: AppColors.accentTintPairOf(context).$2, size: 22),
                                          const SizedBox(height: 8),
                                          Text(appState.plantsLoadError, textAlign: TextAlign.center, style: AppTypography.body(AppColors.textSecondaryOf(context))),
                                          const SizedBox(height: 6),
                                          Text('Tap to retry', style: AppTypography.bodyStrong(AppColors.accentTintPairOf(context).$2)),
                                        ],
                                      ),
                                    )
                                  : Text(
                                      appState.hasActiveFilters ? 'No plants match these filters.' : 'No plants yet — tap Scan to add your first one.',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.body(AppColors.textSecondaryOf(context)),
                                    ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: activeList.length,
                        itemBuilder: (context, i) {
                          final plant = activeList[i];
                          return PlantCard(
                            plant: plant,
                            onTap: () {
                              appState.selectedPlantId = plant.id;
                              appState.goTo('plantDetail');
                            },
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}

class _GardenWishlistToggle extends StatelessWidget {
  final bool showWishlist;
  final int wishlistCount;
  final ValueChanged<bool> onChanged;
  const _GardenWishlistToggle({required this.showWishlist, required this.wishlistCount, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.sageTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        children: [
          Expanded(child: _segment(context, label: 'My garden', selected: !showWishlist, onTap: () => onChanged(false))),
          Expanded(
            child: _segment(
              context,
              label: wishlistCount > 0 ? 'Wishlist ($wishlistCount)' : 'Wishlist',
              selected: showWishlist,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: selected ? AppTypography.bodyStrong(AppColors.textOf(context)) : AppTypography.body(AppColors.textSecondaryOf(context)),
        ),
      ),
    );
  }
}
