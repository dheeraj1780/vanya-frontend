import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../config/plans.dart';
import '../config/web.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

// ============================== Plan ==============================
/// Current tier + live usage against it — the spec's "Usage UI" section:
/// "Show detailed usage primarily inside the subscription/profile/usage
/// section." Refreshes entitlement on open so numbers are never stale from
/// whatever screen the user was last on.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().refreshEntitlement());
  }

  /// Was a standalone "Refresh subscription" settings screen — moved here
  /// since this is the one place it's actually relevant: right after
  /// paying on the website, in case the app-resume auto-refresh (see
  /// AppState.handleAppResumed) hasn't caught up yet.
  Future<void> _handleRefresh() async {
    setState(() => _refreshing = true);
    await context.read<AppState>().refreshEntitlement();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ent = appState.entitlement;
    final plan = kPlans[ent?.plan ?? 'plantie']!;
    final isPaid = ent?.isPaidPlan ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'settings')),
        title: const Text('Plan'),
        actions: [
          IconButton(
            tooltip: 'Check for updates',
            onPressed: _refreshing ? null : _handleRefresh,
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.sync, color: AppColors.primary),
          ),
        ],
      ),
      body: ent == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isPaid ? AppColors.primaryTintPairOf(context).$1 : null,
                    border: Border.all(color: isPaid ? AppColors.primary : AppColors.borderOf(context), width: isPaid ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CURRENT PLAN', style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context), letterSpacing: 0.4)),
                      const SizedBox(height: 4),
                      Text('${plan.emoji} ${plan.displayName}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textOf(context))),
                      const SizedBox(height: 2),
                      Text(plan.tagline, style: Theme.of(context).textTheme.bodyMedium),
                      if (isPaid && ent.expiresAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Renews ${ent.expiresAt!.toLocal().toString().split(' ')[0]}', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('THIS WEEK & MONTH', style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context), letterSpacing: 0.4)),
                const SizedBox(height: 8),
                _UsageRow(label: 'Plant identification', usage: ent.identification, icon: Icons.center_focus_strong_outlined),
                const SizedBox(height: 8),
                _UsageRow(label: 'Care Calculator', usage: ent.careCalculator, icon: Icons.calculate_outlined),
                const SizedBox(height: 8),
                _UsageRow(label: 'Diagnose', usage: ent.diagnose, icon: Icons.healing_outlined),
                const SizedBox(height: 8),
                _PlantSlotRow(plantCount: ent.plantCount, plantLimit: ent.plantLimit),
                const SizedBox(height: 8),
                _WishlistRow(wishlist: ent.wishlist),
                if (ent.gardenSetup.total > 0) ...[
                  const SizedBox(height: 8),
                  _GardenSetupRow(gardenSetup: ent.gardenSetup),
                ],
                if (ent.growthMemories.isAvailable) ...[
                  const SizedBox(height: 8),
                  _GrowthMemoryRow(growthMemories: ent.growthMemories),
                ],
                const SizedBox(height: 20),
                if (isPaid)
                  SecondaryButton(
                    label: 'Manage on vanya.app',
                    icon: Icons.open_in_new,
                    onPressed: () async {
                      // Subscriptions are Razorpay-billed on the website
                      // (see paywall_screen.dart) — this app never builds
                      // its own cancel/change UI, same principle as
                      // deferring to a store's own management flow would
                      // have been, just pointed at our own site instead.
                      final uri = Uri.parse('$kVanyaWebUrl/account');
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('Could not open $kVanyaWebUrl/account: $e');
                      }
                    },
                  )
                else if (ent.nextPlan != null)
                  PrimaryButton(
                    label: 'Upgrade to ${ent.nextPlanDisplayName}',
                    onPressed: () => appState.goTo('paywall', withReturnTo: 'plan'),
                  ),
                const SizedBox(height: 14),
                Text(
                  isPaid
                      ? 'Cancellations and plan changes are handled on vanya.app, not this screen.'
                      : 'Your plants are always safe — even past a plan\'s limit, nothing is ever deleted when a plan changes.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final String label;
  final FeatureUsage usage;
  final IconData icon;
  const _UsageRow({required this.label, required this.usage, required this.icon});

  @override
  Widget build(BuildContext context) {
    final periodLabel = switch (usage.period) {
      'weekly' => 'this week',
      'monthly' => 'this month',
      _ => 'total',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: usage.atLimit ? AppColors.accent : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  usage.isUnlimited ? 'Unlimited' : '${usage.used} / ${usage.limit} $periodLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (usage.resetsAt != null)
                  Text(
                    'Resets ${usage.resetsAt!.toLocal().toString().split(' ')[0]}',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textSecondaryOf(context)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantSlotRow extends StatelessWidget {
  final int plantCount;
  final int plantLimit;
  const _PlantSlotRow({required this.plantCount, required this.plantLimit});

  @override
  Widget build(BuildContext context) {
    final atLimit = plantCount >= plantLimit;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(Icons.eco_outlined, size: 17, color: atLimit ? AppColors.accent : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Plants in your garden', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('$plantCount / $plantLimit — permanent slots, never reset', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistRow extends StatelessWidget {
  final WishlistUsage wishlist;
  const _WishlistRow({required this.wishlist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark_border, size: 17, color: wishlist.atLimit ? AppColors.accent : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wishlist', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('${wishlist.count} / ${wishlist.limit} — plants saved for later, no garden slot used', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthMemoryRow extends StatelessWidget {
  final GrowthMemoryUsage growthMemories;
  const _GrowthMemoryRow({required this.growthMemories});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(Icons.eco_outlined, size: 17, color: growthMemories.atLimit ? AppColors.accent : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Growth Journey', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  growthMemories.isUnlimited
                      ? '${growthMemories.count} memories saved — unlimited on your plan'
                      : '${growthMemories.count} / ${growthMemories.limit} — a one-time growth memory on Green Thumb',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GardenSetupRow extends StatelessWidget {
  final GardenSetup gardenSetup;
  const _GardenSetupRow({required this.gardenSetup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.sageTintPairOf(context).$1, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 17, color: AppColors.sage),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Garden setup', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  gardenSetup.remaining > 0
                      ? '${gardenSetup.remaining} of ${gardenSetup.total} left — a one-time bonus for digitizing plants you already own'
                      : 'Used all ${gardenSetup.total} — new identifications now draw from your regular weekly allowance',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================== Notifications ==============================
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  PermissionStatus? _permission;
  bool _remindersEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Live check, per the same principle established in PermissionsScreen —
    // never trust a cached value for a device-level permission.
    final status = await Permission.notification.status;
    final appState = context.read<AppState>();
    bool remembered = true;
    try {
      remembered = await appState.api.getPreferences(appState.token!);
    } catch (e) {
      debugPrint('Failed to load preferences: $e');
    }
    if (!mounted) return;
    setState(() {
      _permission = status;
      _remindersEnabled = remembered;
      _loading = false;
    });
  }

  /// BUG-R001 (same root cause as RemindersScreen._toggle, which this
  /// duplicates): NotificationService.cancelAll() throwing used to be
  /// caught by the same try/catch guarding the actual preference save,
  /// reverting the switch back to "on" even after the preference had
  /// already persisted successfully — looked like the toggle could never
  /// actually be turned off. Only a real failure to save the preference
  /// reverts it now; a local-notification hiccup after that is best-effort.
  Future<void> _toggle() async {
    final next = !_remindersEnabled;
    setState(() => _remindersEnabled = next); // optimistic
    final appState = context.read<AppState>();
    appState.setRemindersEnabled(next);
    try {
      await appState.api.updatePreferences(appState.token!, next);
    } catch (e) {
      if (mounted) setState(() => _remindersEnabled = !next); // revert on failure
      appState.setRemindersEnabled(!next);
      return;
    }
    // This preference is what actually gates whether watering reminders
    // are scheduled at all — see NotificationService/RemindersScreen.
    try {
      if (next) {
        await NotificationService.instance.scheduleAll(appState.plants);
      } else {
        await NotificationService.instance.cancelAll();
      }
    } catch (e) {
      debugPrint('Reminders preference saved, but local notifications could not be ${next ? "scheduled" : "cancelled"}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final granted = _permission == PermissionStatus.granted;
    final noPlants = appState.plants.isEmpty;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => appState.goBack(fallback: 'settings')), title: const Text('Notifications')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.borderOf(context)), borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(granted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 17, color: granted ? AppColors.primary : AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(granted ? 'Enabled' : 'Disabled', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          granted ? 'Watering reminders will appear at the scheduled time.' : 'Enable notifications in your device settings to get watering reminders.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!granted)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SecondaryButton(label: 'Open device settings', onPressed: openAppSettings),
              ),
            const SizedBox(height: 14),
            Opacity(
              opacity: _loading ? 0.5 : 1,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Watering reminders', style: TextStyle(fontSize: 13)),
                // BUG-R002: nothing to remind about with zero plants (most
                // visible in fresh guest mode) — same fix as RemindersScreen.
                subtitle: noPlants ? const Text('Add a plant first — there\'s nothing to remind you about yet.', style: TextStyle(fontSize: 11.5)) : null,
                value: _remindersEnabled,
                activeThumbColor: AppColors.primary,
                onChanged: (_loading || noPlants) ? null : (_) => _toggle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================== Camera access ==============================
class CameraSettingsScreen extends StatefulWidget {
  const CameraSettingsScreen({super.key});
  @override
  State<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<CameraSettingsScreen> {
  PermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    Permission.camera.status.then((s) {
      if (mounted) setState(() => _permission = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final granted = _permission == PermissionStatus.granted;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.read<AppState>().goBack(fallback: 'settings')), title: const Text('Camera access')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.borderOf(context)), borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(granted ? Icons.camera_alt_outlined : Icons.no_photography_outlined, size: 17, color: granted ? AppColors.primary : AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_permission == null ? 'Checking…' : (granted ? 'Enabled' : 'Disabled'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          granted ? 'Used only when you add a plant or run a diagnosis — never in the background.' : 'Camera access is needed to identify plants and diagnose problems.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_permission != null && !granted)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SecondaryButton(label: 'Open device settings', onPressed: openAppSettings),
              ),
          ],
        ),
      ),
    );
  }
}

