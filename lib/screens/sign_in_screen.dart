import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../config/feature_flags.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/restorable_account_dialog.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String _status = 'idle';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Consumed once — AppState.sessionExpiredMessage is only ever set by
    // _handleSessionExpired (a dead-token 401 forcing this screen open),
    // never by a normal logout/first-launch path to sign-in. Read+clear
    // it here so it explains itself once, not on every future visit.
    final appState = context.read<AppState>();
    final message = appState.sessionExpiredMessage;
    if (message != null) {
      appState.sessionExpiredMessage = null;
      _errorMessage = message;
    }
  }

  /// Signs in with Firebase via a native provider credential, then sends
  /// the resulting Firebase ID token to our own backend — same contract
  /// as the web version's signInWithPopup + getIdToken(), just reached via
  /// native SDKs instead of a browser popup.
  Future<void> _completeFirebaseSignIn(fb.AuthCredential credential) async {
    final userCredential = await fb.FirebaseAuth.instance.signInWithCredential(credential);
    // BUG (reported: a brand-new Google account's name wasn't getting
    // auto-captured): for a JUST-created account, the ID token minted as
    // part of this very sign-in call can lag one beat behind the user
    // profile Firebase just populated from the Google credential — a
    // known Firebase SDK race, not specific to this app. getIdToken()
    // without forceRefresh can hand back that stale pre-profile token,
    // silently missing the "name" claim our backend's auto-capture
    // (create_user's name=... — see auth_service.py) reads from. reload()
    // + getIdToken(true) re-mints against the now-fully-populated profile
    // before we ever send it to our backend.
    await userCredential.user!.reload();
    final identityToken = await userCredential.user!.getIdToken(true);
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
    final data = await appState.api.signIn(provider, identityToken: identityToken, deviceUuid: deviceUuid);

    if (!mounted) return;
    final resolved = await resolveSignInResponse(context, appState, data, provider: provider, identityToken: identityToken, deviceUuid: deviceUuid);
    if (resolved == null) {
      // Restorable dialog dismissed without a choice — stay on the
      // sign-in screen rather than hanging in a "loading" state.
      setState(() => _status = 'idle');
      return;
    }

    if (!mounted) return;
    await appState.handleSignedIn(resolved);
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
              if (kAppleSignInEnabled) ...[
                SecondaryButton(label: 'Continue with Apple', onPressed: loading ? null : _handleApple),
                const SizedBox(height: 10),
              ],
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

