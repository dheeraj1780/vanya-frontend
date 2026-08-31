import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'plant_image.dart';

/// A plant identified but not yet given a garden slot — lighter than
/// PlantCard (no watering status, since a wishlist plant isn't being
/// actively cared for yet). Tapping the card opens WishlistPlantDetailScreen
/// (species info, Growth Journey, Add to Garden all live there now — this
/// card used to also carry a bare Growth Journey icon of its own, cut per
/// the redesign: one obvious way in, not two competing ones).
class WishlistCard extends StatelessWidget {
  final Plant plant;
  final VoidCallback onMoveToGarden;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final bool moving;

  const WishlistCard({
    super.key,
    required this.plant,
    required this.onMoveToGarden,
    required this.onRemove,
    required this.onTap,
    this.moving = false,
  });

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${plant.nickname}?'),
        content: const Text("This takes it off your wishlist. You can always scan it again later."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) onRemove();
  }

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
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: moving ? null : onTap,
                    child: PlantImage(url: plant.photoUrl, borderRadius: 0),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: moving ? null : () => _confirmRemove(context),
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
                Builder(builder: (context) {
                  final (tint, tintFg) = AppColors.primaryTintPairOf(context);
                  return GestureDetector(
                    onTap: moving ? null : onMoveToGarden,
                    child: Container(
                      width: double.infinity,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scale-up + fade-in dialog, in from a resting 0.9x rather than Flutter's
/// default (a flat fade with no scale) — used for the wishlist remove
/// confirmation. Shares the exact curve/duration GrowthJourneyScreen's own
/// memory-detail dialog already established, kept here as a small reusable
/// helper rather than copy-pasted a third time.
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => Builder(builder: builder),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(curved), child: child),
      );
    },
  );
}
