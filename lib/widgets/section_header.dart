import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Section title used above dashboard/list sections ("Today's care", "My
/// plants") — optionally with a trailing action ("See all", "Filter").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.h2(AppColors.textOf(context))),
        if (trailing != null)
          trailing!
        else if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!, style: AppTypography.bodyStrong(AppColors.primary)),
          ),
      ],
    );
  }
}
