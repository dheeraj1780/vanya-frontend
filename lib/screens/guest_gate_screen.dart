import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

class GuestGateScreen extends StatefulWidget {
  const GuestGateScreen({super.key});
  @override
  State<GuestGateScreen> createState() => _GuestGateScreenState();
}

class _GuestGateScreenState extends State<GuestGateScreen> {
  bool _linking = false;
  String _errorMessage = '';

  Future<void> _completeLink(fb.AuthCredential credential) async {
    final appState = context.read<AppState>();
    final userCredential = await fb.FirebaseAuth.instance.signInWithCredential(credential);
    final identityToken = await userCredential.user!.getIdToken();
    try {
      await appState.handleLinkAccount(identityToken!);
      if (!mounted) return;
      appState.goBack(fallback: appState.returnTo); // returns to wherever this gate was triggered from, now signed in
    } on ApiException catch (err) {
      if (err.errorCode != 'IDENTITY_ALREADY_LINKED') rethrow;
      // This identity already has its own separate, real account — a
      // dead-end error here left a normal user with no idea what to do
      // next besides going all the way back to Settings, logging out,
      // and signing in fresh. Offer to just sign into that existing
      // account directly instead — explicit about the tradeoff, since
      // this guest session's data won't come along (nothing here merges
      // the two accounts, see AppState.switchToExistingAccount).
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
        // handleSignedIn (inside switchToExistingAccount) already
        // navigates to Home on its own — nothing further to do here.
        await appState.switchToExistingAccount(identityToken!);
      }
    }
  }

  Future<void> _handleGoogle() async {
    if (_linking) return; // guards a fast double-tap landing before the button disables
    setState(() {
      _linking = true;
      _errorMessage = '';
    });
    try {
      // Forces the real account picker every time, even if Google's SDK
      // cached a selection from an earlier attempt on this screen —
      // without this, tapping "Continue with Google" again (e.g. to try
      // a different account after "already registered") silently reused
      // the same account, with no picker shown at all.
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {
        // Nothing to sign out of yet (first attempt this session) — fine.
      }
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // cancelled the picker — `finally` below still resets _linking
      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      await _completeLink(credential);
    } on ApiException catch (err) {
      // err.message is always safe to show verbatim. Previously this
      // checked e.toString().contains('IDENTITY_ALREADY_LINKED') to
      // special-case that error — but ApiException.toString() returns
      // the human-readable message ("This account is already linked to
      // a different user"), never the error *code*, so that substring
      // could never actually match; catching ApiException directly and
      // just showing its real message works for that case and every
      // other backend-driven failure, not one hardcoded guess.
      setState(() => _errorMessage = err.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not sign in with Google.');
    } finally {
      // _completeLink's own "already registered" dialog can now resolve
      // via Cancel with no exception thrown at all (the user just chose
      // not to proceed) — without this in a `finally`, that path left
      // _linking stuck true forever and the button permanently disabled.
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _handleApple() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _errorMessage = '';
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final credential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await _completeLink(credential);
    } on ApiException catch (err) {
      setState(() => _errorMessage = err.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not sign in with Apple.');
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_add_alt_1, size: 30, color: AppColors.primary),
              const SizedBox(height: 12),
              Text('Sign in to keep going', style: AppTypography.h1(AppColors.textOf(context))),
              const SizedBox(height: 8),
              Text(appState.guestGateReason, textAlign: TextAlign.center, style: AppTypography.body(AppColors.textSecondaryOf(context))),
              const SizedBox(height: 22),
              SecondaryButton(label: 'Continue with Apple', onPressed: _linking ? null : _handleApple),
              const SizedBox(height: 10),
              SecondaryButton(label: 'Continue with Google', onPressed: _linking ? null : _handleGoogle),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_errorMessage, style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
              ],
              const SizedBox(height: 14),
              TextButton(onPressed: () => appState.goBack(fallback: appState.returnTo), child: const Text('Maybe later')),
            ],
          ),
        ),
      ),
    );
  }
}
