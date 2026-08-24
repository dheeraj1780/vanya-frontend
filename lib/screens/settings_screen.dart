import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_badge.dart';
import '../widgets/primary_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _linking = false;
  String _linkError = '';
  bool _deleting = false;
  bool _loggingOut = false;

  // BUGID-S001: the tap previously had no loading feedback at all — on a
  // slow/cold-starting backend (see AppState.handleLogout's docstring) it
  // just looked dead until the request eventually finished. Same
  // disable-while-in-flight + spinner pattern as Delete account below.
  Future<void> _handleLogout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    await context.read<AppState>().handleLogout();
    // No `if (mounted) setState(...)` needed on success: handleLogout()
    // always ends by switching AppState.screen away from Settings, which
    // unmounts this widget — resetting _loggingOut would be a no-op at best.
  }

  Future<void> _handleDeleteAccount() async {
    final appState = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account, all your plants, and your subscription record. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete account', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await appState.handleDeleteAccount();
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete your account. Please try again.')),
        );
      }
      return;
    }

    // BUGID-S003: deletion used to just silently swap the screen out from
    // under the user with zero feedback — this confirms it actually
    // happened, same as the "are you sure?" dialog above it confirmed on
    // the way in. Shown (and dismissed) *before* navigating away, so it
    // isn't yanked off screen mid-read by the screen change.
    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Account deleted'),
          content: const Text('Your account and all its data have been permanently deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
    appState.resetTo('welcome');
  }

  Future<void> _completeLink(fb.AuthCredential credential) async {
    final appState = context.read<AppState>();
    final userCredential = await fb.FirebaseAuth.instance.signInWithCredential(credential);
    final identityToken = await userCredential.user!.getIdToken();
    await appState.handleLinkAccount(identityToken!);
  }

  Future<void> _linkGoogle() async {
    if (_linking) return; // guards a fast double-tap landing before the button disables
    setState(() {
      _linking = true;
      _linkError = '';
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _linking = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      await _completeLink(fb.GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken));
    } catch (e) {
      setState(() => _linkError = 'Could not link Google account.');
    } finally {
      setState(() => _linking = false);
    }
  }

  Future<void> _linkApple() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _linkError = '';
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      await _completeLink(fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      ));
    } catch (e) {
      setState(() => _linkError = 'Could not link Apple account.');
    } finally {
      setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'home')),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (appState.isGuest)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.accentTintPairOf(context).$1,
                border: Border.all(color: AppColors.accent, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Back up your account', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              'You\'re using a guest account — your plants and any subscription only exist on this device.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(label: 'Link Apple account', onPressed: _linking ? null : _linkApple),
                  const SizedBox(height: 8),
                  SecondaryButton(label: 'Link Google account', onPressed: _linking ? null : _linkGoogle),
                  if (_linkError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_linkError, style: const TextStyle(color: AppColors.accent, fontSize: 12)),
                    ),
                ],
              ),
            ),
          Container(
            // Border drawn by the outer Container; background/shape/ink by
            // the inner Material — a plain Container+BoxDecoration
            // background here would hide ListTile's ink splashes (it
            // paints on the nearest Material ancestor, not this box).
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: AppColors.surfaceOf(context),
              child: Column(
                children: [
                  _Row(
                    label: 'Plan',
                    trailingWidget: PlanBadge(planKey: appState.entitlement?.plan ?? (appState.isGuest ? 'guest' : 'plantie'), compact: true),
                    onTap: () => appState.goTo('plan'),
                  ),
                  const Divider(height: 1),
                  _Row(label: 'Notifications', onTap: () => appState.goTo('notifications')),
                  const Divider(height: 1),
                  _Row(label: 'Camera access', onTap: () => appState.goTo('camera')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: AppColors.surfaceOf(context),
              child: ListTile(
                onTap: _loggingOut ? null : _handleLogout,
                title: Text(
                  _loggingOut ? 'Logging out…' : (appState.isGuest ? 'Log out (guest data will be lost)' : 'Log out'),
                  style: AppTypography.bodyStrong(AppColors.accent),
                ),
                trailing: _loggingOut
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : const Icon(Icons.logout, size: 16, color: AppColors.accent),
              ),
            ),
          ),
          if (!appState.isGuest) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: AppColors.surfaceOf(context),
                child: ListTile(
                  onTap: _deleting ? null : _handleDeleteAccount,
                  title: Text(
                    _deleting ? 'Deleting…' : 'Delete account',
                    style: AppTypography.bodyStrong(AppColors.accent),
                  ),
                  trailing: _deleting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                      : const Icon(Icons.delete_outline, size: 16, color: AppColors.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget? trailingWidget;
  final VoidCallback onTap;
  const _Row({required this.label, this.trailingWidget, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: AppTypography.bodyStrong(AppColors.textOf(context))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingWidget != null) trailingWidget!,
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondaryOf(context)),
        ],
      ),
    );
  }
}
