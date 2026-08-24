import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _requesting = false;

  Future<void> _handleAllow() async {
    setState(() => _requesting = true);
    // Real requests — same principle as the React version's Permissions.jsx:
    // this result is never cached as a gate for later actions. Every
    // screen that actually needs camera/notification access re-checks live
    // via Permission.camera.status / Permission.notification.status right
    // before use, since the OS-level grant can change at any time from the
    // device's own Settings app without the user reopening this app.
    await Permission.camera.request();
    await Permission.notification.request();
    if (!mounted) return;
    setState(() => _requesting = false);
    context.read<AppState>().goTo('signin');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Two quick permissions',
                textAlign: TextAlign.center,
                style: AppTypography.h1(AppColors.textOf(context)),
              ),
              const SizedBox(height: 18),
              _PermissionCard(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                desc: 'To identify and diagnose your plants',
              ),
              const SizedBox(height: 10),
              _PermissionCard(
                icon: Icons.notifications_none,
                title: 'Notifications',
                desc: 'To remind you when it\'s watering day',
              ),
              const Spacer(),
              PrimaryButton(
                label: _requesting ? 'Requesting…' : 'Allow and continue',
                loading: _requesting,
                onPressed: _requesting ? null : _handleAllow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _PermissionCard({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: AppColors.primaryTintPairOf(context).$2),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
