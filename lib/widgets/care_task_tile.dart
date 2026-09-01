import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One row in a "Today's care" list — small icon, task text, optional
/// action. Used on Home's care summary and RemindersScreen's due list.
class CareTaskTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool urgent;
  final VoidCallback? onTap;
  final Widget? trailing;

  const CareTaskTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.urgent = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final (tint, color) = urgent ? AppColors.accentTintPairOf(context) : AppColors.primaryTintPairOf(context);

    // Flat tinted surface, not a white-with-border box on the cream page
    // background — a bordered white card here was one more hard edge
    // competing with the header/Quick Actions boxes for attention. This
    // reads lighter, and for an overdue/urgent tile the whole row now
    // carries the warm accent tint instead of just a small icon circle,
    // which actually reads as more urgent, not less, despite being less
    // "boxy" overall.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyStrong(AppColors.textOf(context))),
                  const SizedBox(height: 1),
                  Text(subtitle, style: AppTypography.body(AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
            if (trailing != null) trailing! else Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondaryOf(context)),
          ],
        ),
      ),
    );
  }
}
