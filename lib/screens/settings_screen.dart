import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/restorable_account_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _linking = false;
  String _linkError = '';
  bool _deleting = false;
  bool _savingName = false;

  /// Fallback for accounts that never captured a name automatically —
  /// Apple only sends one on that identity's very first sign-in ever, and
  /// a guest has no identity to pull one from at all — plus anyone who
  /// just wants to change what's there. Pre-filled with the current name
  /// (or blank); saving an empty value clears it back to no name.
  Future<void> _editName() async {
    final appState = context.read<AppState>();
    final controller = TextEditingController(text: appState.userName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          // Was 100 — genuinely no real name needs that much room, and it
          // let someone drag the counter/field into looking broken. 50 is
          // plenty (comfortably covers real full names, incl. longer
          // South/Southeast Asian and multi-part Western ones) without the
          // dialog inviting essay-length input.
          maxLength: 50,
          decoration: const InputDecoration(hintText: 'e.g. Priya'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !mounted) return; // dialog dismissed without Save

    setState(() => _savingName = true);
    try {
      await appState.updateUserName(newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your name. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }
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
          'This deletes your account, all your plants, and your subscription record. '
          'You\'ll have 24 hours to change your mind — see the next step.',
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
    if (!mounted) return;

    // A stronger, typed confirmation for something this consequential —
    // the plain Cancel/Delete dialog above is easy to tap through without
    // really reading it.
    final typedConfirmed = await showDialog<bool>(context: context, builder: (_) => const _DeleteTypedConfirmDialog());
    if (typedConfirmed != true) return;
    if (!mounted) return;

    setState(() => _deleting = true);
    DateTime restorableUntil;
    try {
      restorableUntil = await appState.handleDeleteAccount();
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
    // isn't yanked off screen mid-read by the screen change. Now also
    // states the 24h restore window, since deletion is no longer instant
    // and irreversible the moment this dialog appears.
    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Account deleted'),
          content: Text(
            'Your account has been deleted. If you sign back in before '
            '${formatFriendlyDeadline(restorableUntil)}, you\'ll be able to restore your data and continue — '
            'or start fresh with a new account instead. After that, it\'s gone for good.',
          ),
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
    // See sign_in_screen.dart's _completeFirebaseSignIn for why: a brand-
    // new account's first ID token can be minted just before Firebase
    // finishes populating the profile from the provider credential, so
    // getIdToken() alone can silently miss the "name" claim.
    await userCredential.user!.reload();
    final identityToken = await userCredential.user!.getIdToken(true);
    try {
      await appState.handleLinkAccount(identityToken!);
    } on ApiException catch (err) {
      if (err.errorCode != 'IDENTITY_ALREADY_LINKED') rethrow;
      // This identity already has its own separate, real account — a
      // dead-end error here left a normal user with no idea what to do
      // next besides logging out and signing in fresh themselves. Offer
      // to just sign into that existing account directly instead —
      // explicit about the tradeoff, since this guest session's data
      // won't come along (nothing here merges the two accounts, see
      // AppState.switchToExistingAccount).
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Already registered'),
          content: const Text(
            'This account is already registered with VANYA. Continuing will sign you into that '
            "account instead — your guest plants and data won't come with it, since they're not "
            'linked to it. Continue anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue, lose guest data', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (proceed == true) {
        final data = await appState.switchToExistingAccount(identityToken!);
        if (!mounted) return;
        // The "existing account" can itself be one deleted less than 24h
        // ago — resolveSignInResponse shows the same restore-or-start-fresh
        // choice normal sign-in does if so; a plain signed_in response
        // passes straight through. handleSignedIn then navigates to Home.
        final resolved = await resolveSignInResponse(context, appState, data, provider: 'firebase', identityToken: identityToken);
        if (resolved != null) await appState.handleSignedIn(resolved);
      }
    }
  }

  Future<void> _linkGoogle() async {
    if (_linking) return; // guards a fast double-tap landing before the button disables
    setState(() {
      _linking = true;
      _linkError = '';
    });
    try {
      // Forces the real account picker every time, even if Google's SDK
      // cached a selection from an earlier attempt on this screen —
      // without this, tapping "Link Google account" again (e.g. to try
      // a different account after "already registered") silently reused
      // the same account, with no picker shown at all.
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {
        // Nothing to sign out of yet (first attempt this session) — fine.
      }
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _linking = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      await _completeLink(fb.GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken));
    } on ApiException catch (err) {
      // err.message is always safe to show verbatim (see sign_in_screen's
      // equivalent handling) — this is what was actually hiding the real
      // reason (usually "This account is already linked to a different
      // user" — the Google account was already used to sign in normally
      // at some point) behind a useless generic message.
      setState(() => _linkError = err.message);
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
    } on ApiException catch (err) {
      setState(() => _linkError = err.message);
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
                    label: 'Name',
                    trailingWidget: _savingName
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : ConstrainedBox(
                            // Caps how wide the name can get before it starts
                            // eating into the chevron/row edge — names are
                            // allowed up to 50 chars (see _editName), so
                            // without this an unusually long one would blow
                            // out the row width instead of just truncating.
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              (appState.userName?.isNotEmpty ?? false) ? appState.userName! : 'Add your name',
                              style: TextStyle(
                                color: (appState.userName?.isNotEmpty ?? false) ? AppColors.textOf(context) : AppColors.textSecondaryOf(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    onTap: _savingName ? () {} : _editName,
                  ),
                  const Divider(height: 1),
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

/// The typed "DELETE CONFIRM" step in _handleDeleteAccount — its own
/// StatefulWidget (not inline in a builder) since the Confirm button's
/// enabled state needs to react to every keystroke, which a plain
/// showDialog builder can't do without its own state to rebuild from.
class _DeleteTypedConfirmDialog extends StatefulWidget {
  const _DeleteTypedConfirmDialog();
  @override
  State<_DeleteTypedConfirmDialog> createState() => _DeleteTypedConfirmDialogState();
}

class _DeleteTypedConfirmDialogState extends State<_DeleteTypedConfirmDialog> {
  static const _phrase = 'DELETE CONFIRM';
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Last step'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type "$_phrase" below to permanently delete your account.'),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: _phrase),
            onChanged: (value) => setState(() => _matches = value.trim() == _phrase),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete account', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
      ],
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
