import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatusTone { healthy, attention, neutral }

/// Small pill used for plant health/watering status ("Healthy", "Water in
/// 2 days", "Overdue") — the one place status color-coding is decided, so
/// every card/screen reads it the same way instead of picking colors ad hoc.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;

  const StatusBadge({super.key, required this.label, this.tone = StatusTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusTone.healthy => AppColors.primaryTintPairOf(context),
      StatusTone.attention => AppColors.accentTintPairOf(context),
      StatusTone.neutral => AppColors.sageTintPairOf(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          // Flexible + ellipsis, not a bare Text — mainAxisSize.min still
          // demands the text's full natural width from its parent, which
          // overflows when the badge sits somewhere width-constrained
          // (e.g. PlantCard's grid cell with a longer "Water in N days"
          // label). This lets the label shrink instead of overflowing.
          Flexible(
            child: Text(label, style: AppTypography.caption(fg), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
