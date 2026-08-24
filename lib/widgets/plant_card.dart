import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'plant_image.dart';
import 'status_badge.dart';

/// Image-forward plant card — the one card used for both the My Plants
/// grid and Home's plant preview strip (a fixed-width SizedBox around it
/// gets the horizontal-strip look; letting it fill a grid cell gets the
/// grid look, same widget either way so both screens stay visually
/// identical).
class PlantCard extends StatelessWidget {
  final Plant plant;
  final VoidCallback onTap;

  const PlantCard({super.key, required this.plant, required this.onTap});

  bool get _needsWater {
    final days = plant.nextWateringDue.difference(DateTime.now()).inHours / 24;
    return days <= 0;
  }

  String get _wateringLabel {
    final days = plant.nextWateringDue.difference(DateTime.now()).inHours / 24;
    if (days <= 0) return 'Water now';
    if (days < 1) return 'Water today';
    return 'Water in ${days.ceil()} day${days.ceil() == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        // Expanded (not a fixed AspectRatio) for the image, so the card
        // always exactly fits whatever height its parent gives it — a grid
        // cell sized by childAspectRatio in one place, a fixed-height
        // SizedBox in another. A fixed aspect ratio here previously did
        // the text block's height math for only one of those contexts,
        // overflowing in the other.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PlantImage(url: plant.photoUrl, borderRadius: 0)),
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
                  StatusBadge(
                    label: _wateringLabel,
                    tone: _needsWater ? StatusTone.attention : StatusTone.healthy,
                    icon: Icons.water_drop_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
