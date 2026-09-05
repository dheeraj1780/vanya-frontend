import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the premium plant-care redesign — nature-inspired,
/// calm, editorial. Every screen in the app reads colors/type from here
/// (never a one-off hex value), so the whole app stays visually coherent
/// as new screens get added.
///
/// Field NAMES are kept stable from the previous palette (`primary`,
/// `accent`, `bgLight`, etc.) so the ~15 existing screens that already
/// reference `AppColors.x` repaint automatically with the new values —
/// only the VALUES changed, plus new tokens were added for the new
/// components (PlantCard, CustomBottomNav, StatusBadge, ...).
class AppColors {
  // ---- Core brand — deep forest green family ----
  static const primary = Color(0xFF1F3D30); // deep forest green — primary actions, nav, selected states
  static const primaryDark = Color(0xFF14281F); // pressed state / gradient end
  static const primaryTint = Color(0xFFDCEBE0); // soft mint — chip/selected backgrounds
  static const sage = Color(0xFF7E9887); // sage green — secondary icons, muted accents
  static const sageTint = Color(0xFFE7EEE6);

  // ---- Warm neutrals — cream/off-white, not pure white ----
  static const bgLight = Color(0xFFF7F3EA); // main app background — warm cream
  static const surfaceLight = Color(0xFFFFFDF8); // card surfaces — warm off-white, not pure #FFF
  static const borderLight = Color(0xFFE9E2D2); // hairline borders — warm, low-contrast
  static const textLight = Color(0xFF23281F); // primary text — near-black charcoal, not pure black
  static const textSecondaryLight = Color(0xFF767F70); // secondary/muted text

  // ---- Status accent — warm terracotta (used sparingly: alerts, "needs water") ----
  static const accent = Color(0xFFC17A4F);
  static const accentTint = Color(0xFFF3E3D3);

  // ---- Earth — the app's second brand color, a deliberate deep soil
  // brown (not the lighter, more orange accent above — that stays
  // reserved for alerts, so "this is brand-brown" never reads as "this is
  // a warning"). The split mirrors the app's own logo: a brown roofline/
  // structure with a green leaf sprouting out of it — green is growth/
  // the primary action, brown is the grounded structure around it. Used
  // deliberately, not scattered: SecondaryButton (every "other" action
  // next to a green PrimaryButton), the bottom nav's Scan button (the one
  // ACTION among four navigation destinations), and soil content
  // specifically (plant_facts_screen's Soil section) — never plant-health
  // signaling (StatusBadge's healthy/attention tones stay green/terracotta,
  // so brand color never gets confused with a health status).
  static const earth = Color(0xFF8C5A34); // warm soil brown
  static const earthDark = Color(0xFF6B4326); // pressed state
  static const earthTint = Color(0xFFEFE1D2); // soft warm tan — chip/selected backgrounds
  static const earthTintOnDark = Color(0xFF3A2A1C);
  // Brightened for the same reason primaryOnDark exists — raw `earth`
  // against a near-black dark-mode surface tests too low-contrast to read
  // as "selected"/"active", not just "there".
  static const earthOnDark = Color(0xFFD9A876);

  // ---- Dark mode ----
  static const bgDark = Color(0xFF12160F);
  static const surfaceDark = Color(0xFF1C231C);
  static const borderDark = Color(0xFF2C3529);
  static const textDark = Color(0xFFF1EDE2);
  static const textSecondaryDark = Color(0xFFA3AC9B);

  // ---- Dark-mode chip/badge surfaces ----
  // primaryTint/accentTint/sageTint above are light pastels designed to
  // sit on a cream background — reused verbatim on a near-black screen
  // they read as bright, jarring patches (this is what "the button looks
  // yellow" tester feedback traced back to: dark mode was on, and a light
  // tint chip was rendering unmodified against it). These are deep,
  // desaturated dark-mode equivalents instead — a subtly tinted surface
  // rather than a stark light patch. Always fetch via the xOf(context)
  // helpers below rather than reading these directly, same as the paired
  // xForegroundOf() helpers for the text/icon color that sits on them.
  static const primaryTintOnDark = Color(0xFF20362B);
  static const sageTintOnDark = Color(0xFF222A21);
  static const accentTintOnDark = Color(0xFF3B2A1F);

  // primary (deep forest green) is nearly as dark as bgDark itself — using
  // it as foreground text/icon color on the dark tint surfaces above would
  // be almost invisible (~1.4:1 contrast). accent (terracotta) fares only
  // slightly better. These are brightened dark-mode equivalents, paired
  // with primaryTintOnDark/accentTintOnDark. sage already tests at ~5.7:1
  // against sageTintOnDark unchanged, so it has no separate dark variant.
  static const primaryOnDark = Color(0xFF9AC9AC);
  static const accentOnDark = Color(0xFFE2A67B);

  /// The one place widgets should read a tint/foreground pair from —
  /// resolves to the light pastel + brand color in light mode, or the
  /// dark-surface + brightened-foreground pair in dark mode. See the
  /// dark-mode tokens above for why this exists.
  static (Color background, Color foreground) primaryTintPairOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? (primaryTintOnDark, primaryOnDark) : (primaryTint, primary);

  static (Color background, Color foreground) sageTintPairOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? (sageTintOnDark, sage) : (sageTint, sage);

  static (Color background, Color foreground) accentTintPairOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? (accentTintOnDark, accentOnDark) : (accentTint, accent);

  static (Color background, Color foreground) earthTintPairOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? (earthTintOnDark, earthOnDark) : (earthTint, earth);

  // Brightness-aware resolvers for the base surface/text tokens — the
  // other half of the same fix: screens that hardcoded AppColors.surfaceLight/
  // bgLight/borderLight/textLight/textSecondaryLight directly (instead of
  // reading Theme.of(context)) got a light-mode card or a near-invisible
  // near-black-on-near-black label the instant the OS switched to dark
  // mode, regardless of AppTheme.dark existing at all. Every screen-level
  // widget should read these instead of the bare xLight constant now.
  static Color textOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textDark : textLight;

  static Color textSecondaryOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textSecondaryDark : textSecondaryLight;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceDark : surfaceLight;

  static Color bgOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? bgDark : bgLight;

  static Color borderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? borderDark : borderLight;

  // Legacy aliases some earlier code reads directly.
  static const gradientStart = primaryDark;
  static const gradientEnd = sage;

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, sage],
  );

  /// Soft placeholder gradient for plant photos that haven't loaded/don't
  /// exist yet — reads as "leafy" rather than a blank gray box.
  static const LinearGradient placeholderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sageTint, primaryTint],
  );

  static const LinearGradient placeholderGradientOnDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sageTintOnDark, primaryTintOnDark],
  );

  static LinearGradient placeholderGradientOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? placeholderGradientOnDark : placeholderGradient;
}

/// Spacing/radius scale — keeps every card/button/gap consistent instead of
/// one-off magic numbers scattered per screen.
class AppRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Typography hierarchy — Bricolage Grotesque for display/heading moments
/// (page titles, plant names), paired with Figtree for body/UI text.
/// Chosen together, deliberately, as a production font pass: the previous
/// pairing (Fraunces + Inter) wasn't wrong, but a warm literary serif
/// plus the single most common "safe" UI sans reads as generic-editorial
/// rather than distinctly itself — and Inter specifically is one of the
/// two faces (with Space Grotesk) that shows up so often in AI-assisted
/// design that it's become a tell on its own. Bricolage is the one
/// genuinely un-serif display option in that pass — contemporary and a
/// little quirky without tipping into illegible — and Figtree carries
/// that same modern energy down into UI sizes while staying easy to
/// scan for actual care instructions, which a display face alone can't
/// promise. Field names kept typeface-neutral (not "_serifBase") since
/// the display face isn't a serif any more.
class AppTypography {
  static TextStyle get _displayBase => GoogleFonts.bricolageGrotesque();
  static TextStyle get _bodyBase => GoogleFonts.figtree();

  /// Big, bold — welcome/onboarding moments and hero page titles.
  static TextStyle display(Color color) =>
      _displayBase.copyWith(fontSize: 34, fontWeight: FontWeight.w600, color: color, height: 1.08, letterSpacing: -0.4);

  /// Page-level heading (screen titles, plant name on Plant Detail).
  static TextStyle h1(Color color) =>
      _displayBase.copyWith(fontSize: 26, fontWeight: FontWeight.w600, color: color, height: 1.15, letterSpacing: -0.2);

  /// Section heading ("Today's care", "Watering").
  static TextStyle h2(Color color) =>
      _displayBase.copyWith(fontSize: 19, fontWeight: FontWeight.w600, color: color, height: 1.2);

  /// Card title (plant nickname on a PlantCard).
  static TextStyle h3(Color color) =>
      _bodyBase.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700, color: color, height: 1.25);

  static TextStyle bodyLarge(Color color) => _bodyBase.copyWith(fontSize: 15, fontWeight: FontWeight.w400, color: color, height: 1.5);

  static TextStyle body(Color color) => _bodyBase.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: color, height: 1.5);

  static TextStyle bodyStrong(Color color) => _bodyBase.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: color, height: 1.4);

  static TextStyle caption(Color color) =>
      _bodyBase.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.3, letterSpacing: 0.3);

  /// All-caps eyebrow/section label ("MY PLANTS", "WATERING").
  static TextStyle eyebrow(Color color) =>
      _bodyBase.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: color, height: 1.2, letterSpacing: 0.8);

  static TextStyle button(Color color) => _bodyBase.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600, color: color, height: 1.2);
}

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bgLight,
    fontFamily: GoogleFonts.figtree().fontFamily,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surfaceLight,
    ),
    textTheme: TextTheme(
      headlineMedium: AppTypography.display(Colors.white), // legacy alias used by a couple of hero headers
      titleMedium: AppTypography.h3(AppColors.textLight),
      bodyMedium: AppTypography.body(AppColors.textSecondaryLight),
    ),
    dividerColor: AppColors.borderLight,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: AppTypography.button(Colors.white),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    // Was a neutral bordered button (borderLight/textLight) — every
    // secondary action app-wide now reads as the app's second brand
    // color instead of "primary button's plain, unstyled sibling". See
    // AppColors.earth's own docstring for the green=action/brown=
    // structure rule this follows.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.earth,
        textStyle: AppTypography.button(AppColors.earth),
        side: const BorderSide(color: AppColors.earth, width: 1.3),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary, textStyle: AppTypography.bodyStrong(AppColors.primary)),
    ),
    // A filled, bordered field + a clearly lighter/thinner hint style than
    // the entered-text style (set per-field below) — previously an unset
    // hint defaulted to a color barely distinguishable from a real value.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLight,
      hintStyle: AppTypography.body(AppColors.textSecondaryLight),
      labelStyle: AppTypography.body(AppColors.textSecondaryLight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.borderLight)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.borderLight)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.textLight),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDark,
    fontFamily: GoogleFonts.figtree().fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.sage,
      secondary: AppColors.accent,
      surface: AppColors.surfaceDark,
    ),
    textTheme: TextTheme(
      headlineMedium: AppTypography.display(Colors.white),
      titleMedium: AppTypography.h3(AppColors.textDark),
      bodyMedium: AppTypography.body(AppColors.textSecondaryDark),
    ),
    dividerColor: AppColors.borderDark,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.sage,
        foregroundColor: AppColors.bgDark,
        textStyle: AppTypography.button(AppColors.bgDark),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.earthOnDark,
        textStyle: AppTypography.button(AppColors.earthOnDark),
        side: const BorderSide(color: AppColors.earthOnDark, width: 1.3),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.textDark),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
  );
}
