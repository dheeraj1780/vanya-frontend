import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String _status = 'idle';
  String _errorMessage = '';

  /// Signs in with Firebase via a native provider credential, then sends
  /// the resulting Firebase ID token to our own backend — same contract
  /// as the web version's signInWithPopup + getIdToken(), just reached via
  /// native SDKs instead of a browser popup.
  Future<void> _completeFirebaseSignIn(fb.AuthCredential credential) async {
    final userCredential = await fb.FirebaseAuth.instance.signInWithCredential(credential);
    final identityToken = await userCredential.user!.getIdToken();
    if (!mounted) return;
    await _completeSignIn('firebase', identityToken: identityToken);
  }

  /// Shared by every sign-in path — calls POST /auth/signin, and if the
  /// identity belongs to an account deleted less than 24h ago (see
  /// auth_service.py), shows a restore-or-start-fresh choice before
  /// finishing sign-in with whichever of /auth/restore or /auth/restart
  /// the person picks. A plain "signed_in" response skips straight through.
  Future<void> _completeSignIn(String provider, {String? identityToken, String? deviceUuid}) async {
    final appState = context.read<AppState>();
    var data = await appState.api.signIn(provider, identityToken: identityToken, deviceUuid: deviceUuid);

    if (data['status'] == 'restorable') {
      if (!mounted) return;
      final restorableUntil = parseUtcDateTime(data['restorable_until']);
      final choice = await showDialog<_RestoreChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RestorableAccountDialog(restorableUntil: restorableUntil),
      );

      if (choice == null) {
        // Dialog dismissed without a choice — stay on the sign-in screen
        // rather than hanging in a "loading" state.
        setState(() => _status = 'idle');
        return;
      }

      if (choice == _RestoreChoice.restore) {
        data = await appState.api.restoreAccount(provider, identityToken: identityToken, deviceUuid: deviceUuid);
      } else {
        data = await appState.api.restartAccount(provider, identityToken: identityToken, deviceUuid: deviceUuid);
      }
    }

    if (!mounted) return;
    await appState.handleSignedIn(data);
  }

  Future<void> _handleGoogle() async {
    if (_status == 'loading') return; // guards a fast double-tap landing before the button disables
    setState(() {
      _status = 'loading';
      _errorMessage = '';
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User cancelled the native picker — not an error.
        setState(() => _status = 'idle');
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _completeFirebaseSignIn(credential);
    } on ApiException catch (err) {
      // ApiException.message is always safe to show verbatim — see
      // InternalServerError in the backend's core/exceptions.py, which
      // guarantees it's never a raw exception dump.
      setState(() {
        _status = 'error';
        _errorMessage = err.message;
      });
    } catch (e) {
      // Anything else here is a Firebase/Google SDK exception, not ours —
      // its .toString() previously got shown to the user directly, which
      // is exactly the kind of raw-error leak this screen shouldn't do
      // (see the equivalent fix in guest_gate_screen.dart's _handleGoogle).
      setState(() {
        _status = 'error';
        _errorMessage = 'Could not sign in with Google.';
      });
    }
  }

  Future<void> _handleApple() async {
    if (_status == 'loading') return;
    setState(() {
      _status = 'loading';
      _errorMessage = '';
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauthCredential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await _completeFirebaseSignIn(oauthCredential);
    } on ApiException catch (err) {
      setState(() {
        _status = 'error';
        _errorMessage = err.message;
      });
    } catch (e) {
      setState(() {
        _status = 'error';
        // Apple Sign-In is iOS/macOS-only by default; on Android it needs
        // extra web-auth setup in the Apple Developer console (a "Sign in
        // with Apple" Service ID configured for web) — a real platform
        // requirement on Apple's side, not something to work around here.
        // Not $e here either — see _handleGoogle's equivalent fix.
        _errorMessage = 'Could not sign in with Apple.';
      });
    }
  }

  Future<void> _handleGuest() async {
    if (_status == 'loading') return;
    setState(() {
      _status = 'loading';
      _errorMessage = '';
    });
    try {
      final appState = context.read<AppState>();
      final deviceUuid = await appState.getOrCreateDeviceUuid();
      if (!mounted) return;
      await _completeSignIn('guest', deviceUuid: deviceUuid);
    } on ApiException catch (err) {
      setState(() {
        _status = 'error';
        _errorMessage = err.message;
      });
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = 'Could not sign in. Check that the backend is reachable.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _status == 'loading';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Save your plants', style: AppTypography.h1(AppColors.textOf(context))),
              const SizedBox(height: 6),
              Text(
                'Sign in so your plants and subscription survive a reinstall or new phone.',
                textAlign: TextAlign.center,
                style: AppTypography.body(AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 24),
              SecondaryButton(label: 'Continue with Apple', onPressed: loading ? null : _handleApple),
              const SizedBox(height: 10),
              SecondaryButton(label: 'Continue with Google', onPressed: loading ? null : _handleGoogle),
              const SizedBox(height: 18),
              TextButton(
                onPressed: loading ? null : _handleGuest,
                child: Text(loading ? 'Signing in…' : 'Continue as guest'),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(_errorMessage, style: const TextStyle(color: AppColors.accent, fontSize: 12.5), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _RestoreChoice { restore, restart }

/// Shown when signing back in with an identity whose account was deleted
/// less than 24h ago (see auth_service.sign_in's status="restorable").
/// Deliberately barrier-dismissible: false and requires an explicit tap —
/// no default action is safe to assume on the user's behalf here.
class _RestorableAccountDialog extends StatelessWidget {
  const _RestorableAccountDialog({required this.restorableUntil});

  final DateTime restorableUntil;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Welcome back'),
      content: Text(
        'This account was deleted, but you can still restore it — you have until '
        '${formatFriendlyDeadline(restorableUntil)} to decide. '
        'Restore your plants and pick up where you left off, or start a brand-new account instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_RestoreChoice.restart),
          child: const Text('Start fresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_RestoreChoice.restore),
          child: const Text('Restore my data', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
