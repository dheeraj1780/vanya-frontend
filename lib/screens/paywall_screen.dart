import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../config/plans.dart';
import '../config/web.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/vine_frame.dart';

/// VANYA's tier comparison screen — Plantie -> Green Thumb -> Photosynthesis
/// PhD, per the subscription spec this was built from.
///
/// Deliberately informational ONLY — no purchase flow, no price selection,
/// no "Buy" button. This is Google Play's "reader app" / consumption-only
/// exemption in practice: an app with zero in-app purchase UI pays Google
/// 0% commission on subscriptions, vs. 15-30% via Play Billing. The actual
/// purchase happens on the VANYA website (vanya-web/), which the one link
/// below opens in the device's own browser — never an embedded WebView,
/// since the purchase action must happen fully outside this app to stay
/// compliant. See backend/app/services/billing_service.py's module
/// docstring for the full reasoning and citations.

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  /// Where X/"Not now" should actually go — normally just appState.returnTo,
  /// but after a "Sign in to continue" -> GuestGate round trip, returnTo
  /// becomes 'paywall' itself (see AppState.paywallReturnTo's doc). Falls
  /// back to 'home' only if that ever happens with nothing stashed, which
  /// shouldn't occur in practice but is a safe default over a dead button.
  String get _dismissTarget {
    final appState = context.read<AppState>();
    if (appState.returnTo == 'paywall') return appState.paywallReturnTo ?? 'home';
    return appState.returnTo;
  }

  void _dismiss() {
    final appState = context.read<AppState>();
    final target = _dismissTarget;
    appState.paywallReturnTo = null;
    // dismissTo, not goTo — see AppState.dismissTo's docstring for the
    // exact loop plain goTo() caused here: it pushed 'paywall' itself onto
    // history on the way out, so the very next Back press on `target`
    // (e.g. Growth Journey) landed right back on this paywall.
    appState.dismissTo(target);
  }

  @override
  void initState() {
    super.initState();
    context.read<AppState>().trackEvent('green_thumb_paywall_viewed');
  }

  Future<void> _openWebsite(AppState appState) async {
    appState.trackEvent('subscription_purchase_started');
    // Mint a one-time sign-in handoff token first so the website opens
    // already signed into the SAME account as this app, not a bare sign-in
    // picker — someone with several Google accounts on their phone can
    // easily tap the wrong one there and end up subscribing an account
    // that isn't the one actually using VANYA. Best-effort: a failure here
    // (offline, token service hiccup, ...) still opens the site, just
    // without the handoff — the user can sign in there manually same as
    // before, so this never blocks the purchase entirely.
    String query = '';
    try {
      final handoffToken = await appState.api.createWebHandoffToken(appState.token!);
      query = '?auth_token=${Uri.encodeComponent(handoffToken)}';
    } catch (e) {
      debugPrint('Could not create web handoff token (opening without it): $e');
      // Best-effort fallback: still can't sign the website in directly,
      // but passing the email as a login_hint at least pre-selects/
      // suggests the right Google account in its sign-in picker instead
      // of a blank one — the same wrong-account risk the handoff token
      // exists for, just a weaker mitigation for when that token can't
      // be minted at all (see AppState.userEmail's docstring).
      if (appState.userEmail != null && appState.userEmail!.isNotEmpty) {
        query = '?login_hint=${Uri.encodeComponent(appState.userEmail!)}';
      }
    }
    // externalApplication, never an in-app WebView — the purchase must
    // happen fully outside this app (see class docstring).
    final uri = Uri.parse('$kVanyaWebUrl/upgrade$query');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $kVanyaWebUrl — visit it in your browser to upgrade.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentPlanKey = appState.entitlement?.plan ?? (appState.isGuest ? 'guest' : 'plantie');
    final currentRank = kPlanRank.indexOf(currentPlanKey);
    // Only real upgrades — a Green Thumb user hitting some Green-Thumb-tier
    // limit (e.g. their one Growth Journey memory already used) used to
    // still get offered Green Thumb itself right alongside Photosynthesis
    // PhD, which does nothing for them and just reads as confusing/broken.
    // kPlanRank.indexOf returns -1 for an unrecognized key, which makes
    // this a no-op filter (every real plan ranks above -1) rather than an
    // accidental "show nothing" if currentPlanKey is ever something odd.
    final upgradePlans = kPaidPlanOrder.where((key) => kPlanRank.indexOf(key) > currentRank).toList();

    return Scaffold(
      backgroundColor: AppColors.bgOf(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _dismiss,
                    icon: Icon(Icons.close, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  const Icon(Icons.eco, size: 28, color: AppColors.primary),
                  const SizedBox(height: 10),
                  Text('Grow further with VANYA', style: AppTypography.h1(AppColors.textOf(context))),
                  const SizedBox(height: 6),
                  Text(
                    'More identifications, more Care Calculator runs, more room for your garden.',
                    style: AppTypography.body(AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 20),
                  // Shown as a compact strip, not a full duplicate plan
                  // card below — re-pitching a tier the user already has
                  // right alongside the real upgrade just reads as
                  // confusing ("wait, am I supposed to buy this again?").
                  // Still visibly names it as their current plan though.
                  if (currentRank >= kPlanRank.indexOf('green_thumb'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          PlanBadge(planKey: currentPlanKey, compact: true),
                          const SizedBox(width: 8),
                          Text('Your current plan', style: AppTypography.caption(AppColors.textSecondaryOf(context))),
                        ],
                      ),
                    ),
                  if (upgradePlans.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTintPairOf(context).$1,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.emoji_events_outlined, color: AppColors.primaryTintPairOf(context).$2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "You're already on our top plan — thank you for growing with VANYA 🌳",
                              style: AppTypography.bodyStrong(AppColors.primaryTintPairOf(context).$2),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final planKey in upgradePlans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PlanCard(
                          plan: kPlans[planKey]!,
                          isCurrent: currentPlanKey == planKey,
                          highlight: planKey == 'green_thumb',
                        ),
                      ),
                  const SizedBox(height: 8),
                  if (appState.isGuest) ...[
                    const Text('Sign in first', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('So your subscription is tied to your account, not just this device.', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Sign in to continue',
                      onPressed: () {
                        // Stash paywall's own entry point before this
                        // detour overwrites returnTo with 'paywall' (needed
                        // so GuestGate's own back-navigation lands back
                        // here) — see _dismissTarget.
                        appState.paywallReturnTo = appState.returnTo;
                        appState.guestGateReason = 'Sign in to subscribe.';
                        appState.goTo('guestGate', withReturnTo: 'paywall');
                      },
                    ),
                  ] else ...[
                    Text(
                      'Manage your plan on the VANYA website — sign in there with the same account.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Continue on vanya.app',
                      icon: Icons.open_in_new,
                      onPressed: () => _openWebsite(appState),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(onPressed: _dismiss, child: const Text('Not now')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanConfig plan;
  final bool isCurrent;
  final bool highlight;

  const _PlanCard({required this.plan, required this.isCurrent, required this.highlight});

  @override
  Widget build(BuildContext context) {
    // Green Thumb (the "Most Popular" tier) gets the fuller vine and a
    // soft gradient backdrop — visually the card the eye lands on first.
    final vineColor = highlight ? AppColors.primary : AppColors.sage;

    return VineFrame(
      vineColor: vineColor,
      leafColor: vineColor,
      intensity: highlight ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          gradient: highlight
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryTintPairOf(context).$1, AppColors.surfaceOf(context)])
              : null,
          color: highlight ? null : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: isCurrent ? AppColors.primary : AppColors.borderOf(context), width: isCurrent ? 2 : 1.3),
          boxShadow: highlight ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.surfaceOf(context), shape: BoxShape.circle, border: Border.all(color: AppColors.borderOf(context))),
                  alignment: Alignment.center,
                  child: Text(plan.emoji, style: const TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(plan.displayName, style: AppTypography.h3(AppColors.textOf(context)))),
                // isCurrent checked FIRST — a plan that's both "Most
                // Popular" and the user's actual current plan must say
                // CURRENT, not MOST POPULAR: showing an upsell ribbon on
                // the tier someone is already paying for reads as "buy
                // this again?", not as their status.
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.sageTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: const Text('CURRENT', style: TextStyle(fontSize: 9.5, color: AppColors.sage, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  )
                else if (highlight)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: const Text('MOST POPULAR', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.tagline, style: AppTypography.body(AppColors.textSecondaryOf(context))),
            const SizedBox(height: 10),
            Text(plan.priceLabel, style: AppTypography.display(AppColors.primary).copyWith(fontSize: 26)),
            const SizedBox(height: 12),
            _Feature(text: '${plan.maxPlants} plants in your garden'),
            _Feature(text: '${plan.wishlistLimit} wishlist slots — save plants you like without a garden slot'),
            _Feature(text: plan.identification.humanReadable('identification', 'identifications')),
            _Feature(text: plan.careCalculator.humanReadable('Care Calculator use', 'Care Calculator uses')),
            _Feature(text: plan.diagnose.humanReadable('diagnosis', 'diagnoses')),
            if (plan.gardenSetupIdentifications > 0)
              _Feature(text: '${plan.gardenSetupIdentifications} bonus identifications to set up your garden'),
            if (plan.growthMemoryLimit != 0)
              _Feature(
                text: plan.growthMemoryLimit < 0
                    ? 'Growth Journey — unlimited dated photo memories per plant'
                    : 'Growth Journey — try it with one growth memory',
              ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: AppTypography.body(AppColors.textOf(context)))),
          ],
        ),
      );
}
