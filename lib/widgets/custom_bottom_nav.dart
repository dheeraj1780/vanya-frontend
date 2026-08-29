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

  static const double _pillHeight = 68;
  // How far the raised Scan circle needs to protrude above the pill —
  // matches the old Positioned(top: -38) offset plus a little slack.
  static const double _scanRaise = 34;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      // BUG (reported: "the scan icon isn't working, I had to click on the
      // word"): the raised circle used to be painted via a negative
      // Positioned offset *outside* this whole widget's own box (which was
      // exactly _pillHeight tall). Flutter's hit-testing is bounded by each
      // RenderBox's own resolved size — Clip.none only affects painting,
      // never hit-testing — so taps landing on the visible circle never
      // reached any GestureDetector; only the "Scan" label beneath it,
      // which actually sat inside that box, ever worked.
      //
      // Fix: reserve real height for the circle (_pillHeight + _scanRaise)
      // instead of visual-only overflow, but keep painting the pill
      // background only across its original slim height so the look is
      // unchanged — the Scan button is a second overlay, structurally
      // mirrored (same padding, same four 62-wide slots, same
      // spaceBetween) so its slot lines up exactly with the Row's real one
      // regardless of screen width, without hand-picking a hardcoded X.
      child: SizedBox(
        height: _pillHeight + _scanRaise,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: _pillHeight,
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
                    // Real space reserved for Scan's slot — the tappable
                    // button itself is the overlay below, so its raised
                    // circle isn't clipped down to this pill's own height.
                    const SizedBox(width: 62),
                    _NavItem(icon: Icons.notifications_none, activeIcon: Icons.notifications, label: 'Reminders', selected: current == 'reminders', onTap: onReminders),
                  ],
                ),
              ),
            ),
            // Mirrors the Row above exactly (same outer padding, same
            // four 62-wide items, same spaceBetween) so the real
            // _ScanButton's horizontal position matches the reserved slot
            // precisely, without hardcoding an X offset that would drift
            // on a different screen width.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 62),
                    const SizedBox(width: 62),
                    _ScanButton(onTap: onScan),
                    const SizedBox(width: 62),
                  ],
                ),
              ),
            ),
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
            // The icon/color/weight-only distinction between selected and
            // not was too subtle to read at a glance ("small change in the
            // shade") — a filled pill behind the icon (Material 3's own
            // nav-indicator pattern) makes the current tab unmistakable.
            // Only the WIDTH changes here (22 -> 40), never the height
            // (stays exactly 22 either way), so this can't disturb the
            // label-row alignment across all four bottom-nav items.
            selected
                ? Container(
                    width: 40,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, borderRadius: BorderRadius.circular(11)),
                    child: Icon(activeIcon, size: 20, color: color),
                  )
                : Icon(icon, size: 22, color: color),
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
          // Real height (not just visual overflow) — see the docstring on
          // CustomBottomNav.build for why this matters: it's what makes
          // the raised circle itself tappable, not just the label under it.
          height: CustomBottomNav._pillHeight + CustomBottomNav._scanRaise,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // BUG (reported: "the scan icon has been pushed down" — the
              // label sat visibly lower than Home/My Plants/Reminders'):
              // this used to bottom-align flush against this box's own
              // (taller, _pillHeight + _scanRaise) bottom edge — but
              // _NavItem centers its label within just the pill's own
              // _pillHeight, leaving equal space above and below, so
              // "flush with the very bottom" landed noticeably lower than
              // that. Constraining this to exactly _pillHeight, anchored
              // to the same bottom edge, and centering within *that*
              // (mainAxisAlignment.center, same as _NavItem) reproduces
              // _NavItem's own vertical centering exactly, instead of
              // approximating it.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: CustomBottomNav._pillHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 22, height: 22),
                    const SizedBox(height: 3),
                    Text('Scan', style: AppTypography.caption(AppColors.primary).copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Positioned(
                top: 0,
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
