import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Floating, rounded bottom navigation — replaces the default Material
/// BottomNavigationBar look per the redesign brief. Four destinations:
/// Home, My Plants, Scan (visually emphasized as a raised center button —
/// it's an action shortcut to Add Plant, not a persistent tab), Reminders.
class CustomBottomNav extends StatelessWidget {
  final String current; // 'home' | 'myPlants' | 'reminders' (scan has no "current" state — it's an action)
  final VoidCallback onHome;
  final VoidCallback onMyPlants;
  final VoidCallback onScan;
  final VoidCallback onReminders;

  const CustomBottomNav({
    super.key,
    required this.current,
    required this.onHome,
    required this.onMyPlants,
    required this.onScan,
    required this.onReminders,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', selected: current == 'home', onTap: onHome),
            _NavItem(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view, label: 'My Plants', selected: current == 'myPlants', onTap: onMyPlants),
            _ScanButton(onTap: onScan),
            _NavItem(icon: Icons.notifications_none, activeIcon: Icons.notifications, label: 'Reminders', selected: current == 'reminders', onTap: onReminders),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondaryOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(label, style: AppTypography.caption(color).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // BUG-C002: this was the one bottom-nav destination with no visible
    // label at all — Home/My Plants/Reminders all have one (see _NavItem).
    // Still an icon-first raised circle (that's the intended visual
    // emphasis), just no longer making the icon carry all the meaning by
    // itself: a caption below for sighted users, a Semantics label around
    // the whole button for screen readers (an Icon alone announces nothing
    // meaningful on its own).
    return Semantics(
      button: true,
      label: 'Scan a plant',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 62,
          // BUG-H004: an OverflowBox/Transform combo here still left "Scan"
          // a hair off from Home/My Plants/Reminders' labels — a Transform
          // doesn't add layout height, but OverflowBox's own resolved size
          // (and how it aligns a bigger child within a smaller one) isn't
          // as pixel-predictable as just... not sharing layout space with
          // the label at all. This Stack fully decouples the two: the
          // Column below is byte-for-byte the same shape as _NavItem's
          // (22px slot + 3px gap + label), just with an invisible
          // placeholder instead of a real icon, so "Scan" lands on exactly
          // the same baseline as the other three, guaranteed — the raised
          // circle is a separate Positioned overlay that doesn't
          // participate in that layout at all, purely visual.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 22, height: 22),
                  const SizedBox(height: 3),
                  Text('Scan', style: AppTypography.caption(AppColors.primary).copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              Positioned(
                top: -38,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
