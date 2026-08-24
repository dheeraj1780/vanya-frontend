import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

/// Shows every plant's watering due date and actually schedules the local
/// notifications behind the reminders_enabled preference. A tab-shell body
/// (see main.dart's _TabShell) — no own Scaffold/AppBar.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  bool _toggling = false;
  PermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final status = await Permission.notification.status;
    await appState.refreshPlants();
    if (!mounted) return;
    setState(() {
      _permission = status;
      _loading = false;
    });
  }

  /// BUG-R001: the switch looked stuck permanently "on" — turning it off
  /// never stuck. Root cause was this whole method sharing one try/catch:
  /// NotificationService.cancelAll() (unguarded — see its own definition)
  /// throwing on some devices/platform-channel states took down the *entire*
  /// try block, landing in the catch below, which reverted the toggle back
  /// to `previous` (on) even though the actual preference had already saved
  /// successfully. Now only a genuine failure to persist the preference
  /// reverts the switch; a local-notification hiccup after that point is
  /// best-effort and never undoes a change that already saved.
  Future<void> _toggle(bool next) async {
    final appState = context.read<AppState>();
    if (next) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _permission = status);
        return;
      }
      if (mounted) setState(() => _permission = status);
    }

    setState(() => _toggling = true);
    final previous = appState.remindersEnabled;
    appState.setRemindersEnabled(next); // optimistic
    try {
      await appState.api.updatePreferences(appState.token!, next);
    } catch (e) {
      debugPrint('Failed to update reminders preference: $e');
      appState.setRemindersEnabled(previous);
      if (mounted) setState(() => _toggling = false);
      return;
    }
    try {
      if (next) {
        await NotificationService.instance.scheduleAll(appState.plants);
      } else {
        await NotificationService.instance.cancelAll();
      }
    } catch (e) {
      debugPrint('Reminders preference saved, but local notifications could not be ${next ? "scheduled" : "cancelled"}: $e');
    }
    if (mounted) setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final granted = _permission == PermissionStatus.granted;
    final plants = [...appState.plants]..sort((a, b) => a.nextWateringDue.compareTo(b.nextWateringDue));

    return _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              Text('Reminders', style: AppTypography.h1(AppColors.textOf(context))),
              const SizedBox(height: 18),
              if (!granted)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.accentTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.accentTintPairOf(context).$2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifications are disabled at the device level — reminders can be scheduled below, but nothing will appear until you enable notifications.',
                          style: AppTypography.body(AppColors.textOf(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: AppColors.surfaceOf(context),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    title: Text('Watering reminders', style: AppTypography.bodyStrong(AppColors.textOf(context))),
                    // BUG-R002: there's nothing to remind about with zero
                    // plants (most visible in fresh guest mode) — flipping
                    // the switch there didn't do anything harmful, but it
                    // also did nothing useful, which just reads as broken.
                    subtitle: Text(
                      plants.isEmpty
                          ? 'Add a plant first — there\'s nothing to remind you about yet.'
                          : (appState.remindersEnabled ? 'You\'ll get a notification when each plant is due for water.' : 'Turn on to get notified when a plant needs water.'),
                      style: AppTypography.body(AppColors.textSecondaryOf(context)),
                    ),
                    value: appState.remindersEnabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: (_toggling || plants.isEmpty) ? null : _toggle,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Upcoming'),
              const SizedBox(height: 12),
              if (plants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No plants yet — add one to start tracking watering reminders.', style: AppTypography.body(AppColors.textSecondaryOf(context))),
                )
              else
                for (final plant in plants) _ReminderTile(plant: plant, enabled: appState.remindersEnabled),
            ],
          );
  }
}

class _ReminderTile extends StatelessWidget {
  final Plant plant;
  final bool enabled;
  const _ReminderTile({required this.plant, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final due = plant.nextWateringDue;
    final daysUntil = due.difference(DateTime.now()).inHours / 24;
    final overdue = daysUntil < 0;
    final dueLabel = overdue
        ? 'Overdue by ${(-daysUntil).ceil()} day(s)'
        : daysUntil < 1
            ? 'Due today'
            : 'Due in ${daysUntil.ceil()} day(s)';
    final (tint, tintFg) = overdue ? AppColors.accentTintPairOf(context) : AppColors.primaryTintPairOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(overdue ? Icons.water_drop : Icons.water_drop_outlined, size: 17, color: tintFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plant.nickname, style: AppTypography.bodyStrong(AppColors.textOf(context))),
                Text(
                  enabled ? dueLabel : '$dueLabel · reminders off',
                  style: AppTypography.body(overdue ? AppColors.accent : AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
