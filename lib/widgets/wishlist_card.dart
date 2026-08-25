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
            child: GestureDetector(
              onTap: moving ? null : onOpenGrowthJourney,
              child: PlantImage(url: plant.photoUrl, borderRadius: 0),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Builder(builder: (context) {
                        final (tint, tintFg) = AppColors.primaryTintPairOf(context);
                        return GestureDetector(
                          onTap: moving ? null : onMoveToGarden,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
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
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: moving ? null : onOpenGrowthJourney,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.eco_outlined, size: 16, color: AppColors.sage),
                      ),
                    ),
                    GestureDetector(
                      onTap: moving ? null : onRemove,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 16, color: AppColors.textSecondaryOf(context)),
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
