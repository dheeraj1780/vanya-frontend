import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Shared by every place that can receive a /auth/signin-shaped response
/// whose identity belongs to an account deleted less than 24h ago (see
/// backend auth_service.py's ACCOUNT_RESTORE_WINDOW): the normal sign-in
/// screen, and both "link Google/Apple account" flows' fallback into an
/// existing account (settings_screen.dart / guest_gate_screen.dart). All
/// three used to duplicate this, and the two link-account ones didn't
/// handle a restorable response at all — they just treated any /auth/signin
/// result as an already-completed sign-in, which crashed for a deleted-
/// within-24h identity (see AppState.switchToExistingAccount's docstring).
enum RestoreChoice { restore, restart }

/// Shown when signing back in with an identity whose account was deleted
/// less than 24h ago. Deliberately barrier-dismissible: false and requires
/// an explicit tap — no default action is safe to assume on the user's
/// behalf here.
Future<RestoreChoice?> showRestorableAccountDialog(BuildContext context, DateTime restorableUntil) {
  return showDialog<RestoreChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Welcome back'),
      content: Text(
        'This account was deleted, but you can still restore it — you have until '
        '${formatFriendlyDeadline(restorableUntil)} to decide. '
        'Restore your plants and pick up where you left off, or start a brand-new account instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(RestoreChoice.restart),
          child: const Text('Start fresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(RestoreChoice.restore),
          child: const Text('Restore my data', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Resolves a /auth/signin-shaped response into a final signed_in response:
/// a plain one passes through untouched; a `status: "restorable"` one shows
/// the dialog above and calls /auth/restore or /auth/restart per the
/// choice. Returns null if the dialog was dismissed without a choice — the
/// caller should treat that as "stay put, nothing happened", not an error
/// (the finally-block loading-state resets already in place at every call
/// site cover this, same as a plain Cancel does elsewhere in these flows).
Future<Map<String, dynamic>?> resolveSignInResponse(
  BuildContext context,
  AppState appState,
  Map<String, dynamic> data, {
  required String provider,
  String? identityToken,
  String? deviceUuid,
}) async {
  if (data['status'] != 'restorable') return data;
  final restorableUntil = parseUtcDateTime(data['restorable_until']);
  final choice = await showRestorableAccountDialog(context, restorableUntil);
  if (choice == null) return null;
  return choice == RestoreChoice.restore
      ? await appState.api.restoreAccount(provider, identityToken: identityToken, deviceUuid: deviceUuid)
      : await appState.api.restartAccount(provider, identityToken: identityToken, deviceUuid: deviceUuid);
}
