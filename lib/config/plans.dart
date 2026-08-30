/// Display-only mirror of the backend's app/core/plans.py — the numbers
/// here are ONLY used for paywall/usage copy (pricing, limits, taglines).
/// This app has no purchase flow at all (see paywall_screen.dart — actual
/// subscriptions are sold on the VANYA website, not here), so there's no
/// live store price to fetch or fall back from; this file's price_inr
/// values ARE the displayed price. They are never used to enforce
/// anything: every check that actually blocks an action happens
/// server-side (see entitlement_service.py) — this file existing twice
/// (once per platform) is a deliberate, low-risk duplication of *display*
/// data, not of *enforcement* logic. If pricing changes, update both this
/// file and plans.py to keep the paywall's copy accurate; the app still
/// works correctly even if they briefly drift, since the backend is
/// always the source of truth for what's actually allowed.
library;

class FeatureAllowance {
  final int limit; // -1 = unlimited
  final String period; // "lifetime" | "weekly" | "monthly"
  const FeatureAllowance(this.limit, this.period);

  /// e.g. "3 identifications / week", "1 diagnosis / month" — the spec's
  /// own preferred phrasing over "N credits".
  String humanReadable(String featureNounSingular, String featureNounPlural) {
    final noun = limit == 1 ? featureNounSingular : featureNounPlural;
    final suffix = switch (period) {
      'weekly' => ' / week',
      'monthly' => ' / month',
      _ => ' total',
    };
    return '$limit $noun$suffix';
  }
}

class PlanConfig {
  final String key;
  final String displayName;
  final String tagline;
  final String emoji;
  final int priceInr;
  final String billing; // "none" | "monthly"
  final int maxPlants;
  final int wishlistLimit;
  final int gardenSetupIdentifications;
  final FeatureAllowance identification;
  final FeatureAllowance careCalculator;
  final FeatureAllowance diagnose;
  // Growth Journey — persistent slots for dated photo memories, same
  // PLANT COLLECTION RULES semantics as maxPlants (see plans.py's GROWTH
  // JOURNEY note). 0 = not offered on this tier; -1 = unlimited.
  final int growthMemoryLimit;
  final String? productId;

  const PlanConfig({
    required this.key,
    required this.displayName,
    required this.tagline,
    required this.emoji,
    required this.priceInr,
    required this.billing,
    required this.maxPlants,
    required this.wishlistLimit,
    required this.gardenSetupIdentifications,
    required this.identification,
    required this.careCalculator,
    required this.diagnose,
    required this.growthMemoryLimit,
    this.productId,
  });

  String get priceLabel => priceInr == 0 ? 'Free' : '₹$priceInr/month';
}

const Map<String, PlanConfig> kPlans = {
  'guest': PlanConfig(
    key: 'guest',
    displayName: 'Guest',
    tagline: 'Try VANYA before you sign in.',
    emoji: '🌾',
    priceInr: 0,
    billing: 'none',
    maxPlants: 3,
    wishlistLimit: 3,
    gardenSetupIdentifications: 0,
    identification: FeatureAllowance(3, 'lifetime'),
    careCalculator: FeatureAllowance(3, 'lifetime'),
    diagnose: FeatureAllowance(1, 'lifetime'),
    growthMemoryLimit: 0,
  ),
  'plantie': PlanConfig(
    key: 'plantie',
    displayName: 'Plantie',
    tagline: 'Start your plant journey.',
    emoji: '🌱',
    priceInr: 0,
    billing: 'none',
    maxPlants: 5,
    wishlistLimit: 5,
    gardenSetupIdentifications: 0,
    identification: FeatureAllowance(3, 'weekly'),
    careCalculator: FeatureAllowance(3, 'weekly'),
    diagnose: FeatureAllowance(1, 'monthly'),
    growthMemoryLimit: 0,
  ),
  'green_thumb': PlanConfig(
    key: 'green_thumb',
    displayName: 'Green Thumb',
    tagline: 'Grow your garden with confidence.',
    emoji: '🌿',
    priceInr: 99,
    billing: 'monthly',
    maxPlants: 10,
    wishlistLimit: 20,
    gardenSetupIdentifications: 10,
    identification: FeatureAllowance(7, 'weekly'),
    careCalculator: FeatureAllowance(7, 'weekly'),
    diagnose: FeatureAllowance(2, 'monthly'),
    growthMemoryLimit: 1,
    productId: 'vanya_green_thumb_monthly',
  ),
  'photosynthesis_phd': PlanConfig(
    key: 'photosynthesis_phd',
    displayName: 'Photosynthesis PhD',
    tagline: 'For those who take plants seriously.',
    emoji: '🌳',
    priceInr: 199,
    billing: 'monthly',
    maxPlants: 25,
    wishlistLimit: 50,
    gardenSetupIdentifications: 25,
    identification: FeatureAllowance(10, 'weekly'),
    careCalculator: FeatureAllowance(20, 'weekly'),
    diagnose: FeatureAllowance(5, 'monthly'),
    growthMemoryLimit: -1,
    productId: 'vanya_photosynthesis_phd_monthly',
  ),
};

/// The two paid tiers, in display order — what the paywall renders as
/// purchasable options (Plantie is never purchased, it's granted on
/// sign-in; Guest is never shown on the paywall at all).
const List<String> kPaidPlanOrder = ['green_thumb', 'photosynthesis_phd'];

/// Every tier, worst to best — lets the paywall (and anything else that
/// cares) ask "is plan X actually better than plan Y" instead of just
/// "are these the same string". See PaywallScreen's plan filtering: a
/// Green Thumb user hitting a Green-Thumb-exhausted limit (e.g. their one
/// growth memory already used) should only ever be offered Photosynthesis
/// PhD — re-offering the plan they're already on and which won't fix
/// anything is confusing, not helpful.
const List<String> kPlanRank = ['guest', 'plantie', 'green_thumb', 'photosynthesis_phd'];
