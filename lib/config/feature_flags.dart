/// Simple compile-time feature toggles — not server-driven, just a single
/// place to flip something on/off across every screen that offers it.
library;

/// Sign in / link with Apple is hidden app-wide for now (their handler
/// code, SecondaryButton, and the sign_in_with_apple dependency are all
/// left in place — this only hides the entry points) until Apple's own
/// Service ID / web-auth setup for Android is finished on the Apple
/// Developer console side (see sign_in_screen.dart's _handleApple doc).
/// Google sign-in is unaffected.
const bool kAppleSignInEnabled = false;
