/// The VANYA website's base URL — where subscriptions are actually sold
/// (see paywall_screen.dart for why: Google Play's 0%-commission
/// "reader app" exemption requires this app to have zero in-app purchase
/// UI). Overridable at build time the same way API_BASE_URL is, e.g.:
///   flutter build apk --dart-define=VANYA_WEB_URL=https://vanya.app
const String kVanyaWebUrl = String.fromEnvironment('VANYA_WEB_URL', defaultValue: 'https://vanya-web-eight.vercel.app');
