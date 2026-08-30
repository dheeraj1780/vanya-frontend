import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'plant_image.dart';

/// A plant identified but not yet given a garden slot — lighter than
/// PlantCard (no watering status, since a wishlist plant isn't being
/// actively cared for yet) and carries its own two actions instead of
/// navigating to PlantDetailScreen (which assumes an active, watered plant).
class WishlistCard extends StatelessWidget {
  final Plant plant;
  final VoidCallback onMoveToGarden;
  final VoidCallback onRemove;
  final VoidCallback onOpenGrowthJourney;
  final bool moving;

  const WishlistCard({
    super.key,
    required this.plant,
    required this.onMoveToGarden,
    required this.onRemove,
    required this.onOpenGrowthJourney,
    this.moving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // E-MP004: the big photo used to be inert — only the small eco
          // icon below opened anything. A wishlist plant has no full detail
          // screen (see class docstring), so the photo taps through to the
          // same place that icon does: its Growth Journey.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: moving ? null : onOpenGrowthJourney,
                    child: PlantImage(url: plant.photoUrl, borderRadius: 0),
                  ),
                ),
                // Remove moved here, off the photo's own tap target and
                // physically apart from "Move to garden"/Growth Journey
                // below — those three actions used to all sit in one
                // cramped 4px-gap row, easy to mis-tap ("remove" right next
                // to the two actions someone actually meant to hit).
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: moving ? null : onRemove,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plant.nickname, style: AppTypography.h3(AppColors.textOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  plant.species ?? 'Not identified',
                  style: AppTypography.caption(AppColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Builder(builder: (context) {
                        final (tint, tintFg) = AppColors.primaryTintPairOf(context);
                        return GestureDetector(
                          onTap: moving ? null : onMoveToGarden,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
                            child: Center(
                              child: moving
                                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: tintFg))
                                  : Text('Move to garden', style: AppTypography.caption(tintFg), textAlign: TextAlign.center),
                            ),
                          ),
                        );
                      }),
                    ),
                    // Clear gap (not the old 4px) and its own bordered,
                    // larger tap target — reads as a deliberate second
                    // action next to "Move to garden", not an accidental
                    // extra icon crowding it.
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: moving ? null : onOpenGrowthJourney,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.sageTintPairOf(context).$1,
                        ),
                        child: Icon(Icons.eco_outlined, size: 15, color: AppColors.sage),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
