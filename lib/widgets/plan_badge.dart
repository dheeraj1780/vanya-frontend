import 'package:flutter/material.dart';
import '../config/plans.dart';
import '../theme/app_theme.dart';

/// A small "you are here" tier indicator — emoji + plan name in a
/// tier-colored pill. Used wherever a user should be able to recognize
/// their own status at a glance (Home header, Settings, the Plan screen)
/// without having to open the paywall to remember which tier they're on.
class PlanBadge extends StatelessWidget {
  final String planKey; // "guest" | "plantie" | "green_thumb" | "photosynthesis_phd"
  final bool compact;

  const PlanBadge({super.key, required this.planKey, this.compact = false});

  /// A distinct color identity per tier — Plantie stays the app's own sage
  /// (it's the default, nothing to celebrate yet), Green Thumb gets the
  /// brand's primary forest green (its "hero" tier), Photosynthesis PhD
  /// gets a richer, deeper tone that reads as a step up again.
  (Color, Color) _colors(BuildContext context) {
    switch (planKey) {
      case 'green_thumb':
        return (AppColors.primary, Colors.white);
      case 'photosynthesis_phd':
        return (const Color(0xFF3D2B1F), const Color(0xFFF3E3D3)); // deep bark brown / warm cream — solid, works in both modes
      default:
        return AppColors.sageTintPairOf(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = kPlans[planKey] ?? kPlans['plantie']!;
    final (bg, fg) = _colors(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(plan.emoji, style: TextStyle(fontSize: compact ? 11 : 13)),
          SizedBox(width: compact ? 3 : 5),
          Text(
            plan.displayName,
            style: (compact ? AppTypography.caption(fg) : AppTypography.bodyStrong(fg)).copyWith(fontSize: compact ? 10 : 12),
          ),
        ],
      ),
    );
  }
}
