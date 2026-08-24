# VANYA — Flutter app

Plant identification, care tracking, and diagnosis, talking to the FastAPI
backend in `../plant-companion-backend`.

## Subscriptions — no purchase flow in this app

This app deliberately has **zero in-app purchase UI**. Subscriptions
(Green Thumb / Photosynthesis PhD) are sold on the separate VANYA website
(`../plant-companion-web`), not here — that's Google Play's "reader app" /
consumption-only exemption in practice: an app with no purchase flow at
all pays Google **0% commission**, vs. 15-30% through Play Billing. See
`backend/app/services/billing_service.py`'s module docstring for the full
reasoning, and `lib/screens/paywall_screen.dart`, which only shows tier
info and a link out to the website — never a "Buy" button.

Because of this: **don't add `purchases_flutter`/RevenueCat/any Play
Billing package back into this app.** If a future need for real in-app
billing comes up (a different market, a different compliance posture),
that's a deliberate architecture decision to revisit, not a small addition.

## Setup

### 1. Firebase
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```
Point it at the project the backend's `secrets/firebase_service_account.json`
and the website both already use — this generates `lib/firebase_options.dart`
and `android/app/google-services.json` / `ios/Runner/GoogleService-Info.plist`.

**Android Google Sign-In needs your signing certificate's SHA-1 registered**
in Firebase Console > Project Settings > your Android app > SHA certificate
fingerprints, or sign-in fails with `ApiException: 10` (`DEVELOPER_ERROR`).
Debug builds and release builds are signed with different keys — each needs
its own fingerprint added. Get a keystore's SHA-1 with:
```bash
keytool -list -v -keystore path/to/keystore -alias <alias> -storepass <password>
```
After adding a fingerprint, **re-download `google-services.json`** and
replace the one in `android/app/` — the fingerprint alone doesn't update it.

### 2. Apple Sign-In on Android
`sign_in_with_apple` needs a web-based auth flow configured on Android
(Apple Sign-In is natively iOS-only): a Service ID in your Apple Developer
account with a return URL, passed via `webAuthenticationOptions` to
`getAppleIDCredential()` on Android.

### 3. Point at your backend and the website
```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-backend-domain.com/v1 \
  --dart-define=VANYA_WEB_URL=https://vanya.app
```
`API_BASE_URL` defaults to whatever's in `lib/api/client.dart` (currently a
dev ngrok tunnel — replace before any real beta distribution, ngrok URLs
aren't stable). `VANYA_WEB_URL` defaults to `https://vanya.app` (placeholder
— point it at wherever `plant-companion-web` actually gets deployed).

### 4. Run it
```bash
flutter pub get
flutter analyze
flutter run
```

## Architecture notes

- Single `AppState extends ChangeNotifier` (Provider) drives navigation via
  a string `screen` field, not Flutter's Navigator — see `main.dart`'s
  `RootRouter`.
- `GET /entitlement` is the one source of truth for what the signed-in user
  can do — the app never decides limits locally, only reflects what the
  backend already enforced (see `entitlement_service.py`).
- Every subscription-tier number (prices, limits) lives in
  `lib/config/plans.dart`, a display-only mirror of the backend's
  `app/core/plans.py` — real enforcement is always server-side.
