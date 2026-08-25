/// The backend stores every timestamp as naive UTC (see
/// user_repository.soft_delete_user's docstring on why) — Pydantic then
/// serializes a naive datetime with no 'Z'/offset suffix, which
/// DateTime.parse() on its own would misinterpret as the device's LOCAL
/// time instead of UTC. Used where getting this exactly right actually
/// matters to the user (a restore deadline) rather than just "a few days
/// ago" display text. Safe even if the backend ever does send a proper
/// suffix — won't double one up.
DateTime parseUtcDateTime(String value) =>
    DateTime.parse(value.endsWith('Z') || value.contains('+') ? value : '${value}Z');

const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Tue 6:17 PM" in the device's own local time — used for the
/// account-deletion restore-window deadline (settings_screen.dart's
/// delete-account flow, sign_in_screen.dart's restorable-account choice),
/// shared so the two screens can't drift on the exact phrasing.
String formatFriendlyDeadline(DateTime utc) {
  final local = utc.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  return '${_kWeekdays[local.weekday - 1]} $hour12:$minute $ampm';
}

/// Mirrors PlantItem in the backend's schemas/plant.py — field names match
/// exactly so JSON decoding needs no manual remapping.
class Plant {
  final String id;
  // "active" = in the garden (counts toward plantLimit, gets reminders/
  // calculators/diagnose). "wishlist" = identified but not yet given a
  // garden slot — see WishlistScreen / MyPlantsScreen's toggle.
  final String status;
  final String nickname;
  final String? species;
  final String? speciesConfidence;
  final String? lightNeeds;
  final int waterFrequencyDays;
  final String? photoUrl;
  final DateTime? lastWateredAt;
  final List<String> funFacts;
  // E-MP001: common household/vernacular names this plant goes by in
  // Indian homes (e.g. "Money Plant", "Paisa Paudha") — alongside, not
  // instead of, species/nickname. Empty when the AI had no genuine one.
  final List<String> regionalNames;
  // E-MP002: a named soil type (e.g. "Red soil", "Black soil", "Sandy
  // loam") plus what to mix into it for this species specifically.
  final String? soilType;
  final String? soilAmendments;
  final bool? isIndoor;
  final bool? isPetSafe;
  final bool? isAirPurifying;
  final String? careDifficulty;
  final DateTime createdAt;
  // Growth Journey's background for this plant — "preset:<key>" (a
  // bundled app asset) or a real photo URL (custom gallery pick); null if
  // never chosen. See GrowthJourneyScreen's background picker.
  final String? growthBackground;

  Plant({
    required this.id,
    this.status = 'active',
    required this.nickname,
    this.species,
    this.speciesConfidence,
    this.lightNeeds,
    required this.waterFrequencyDays,
    this.photoUrl,
    this.lastWateredAt,
    this.funFacts = const [],
    this.regionalNames = const [],
    this.soilType,
    this.soilAmendments,
    this.isIndoor,
    this.isPetSafe,
    this.isAirPurifying,
    this.careDifficulty,
    required this.createdAt,
    this.growthBackground,
  });

  factory Plant.fromJson(Map<String, dynamic> json) => Plant(
        id: json['id'],
        status: json['status'] ?? 'active',
        nickname: json['nickname'],
        species: json['species'],
        speciesConfidence: json['species_confidence'],
        lightNeeds: json['light_needs'],
        waterFrequencyDays: json['water_frequency_days'] ?? 7,
        photoUrl: json['photo_url'],
        lastWateredAt: json['last_watered_at'] != null ? parseUtcDateTime(json['last_watered_at']) : null,
        funFacts: (json['fun_facts'] as List?)?.map((e) => e.toString()).toList() ?? [],
        regionalNames: (json['regional_names'] as List?)?.map((e) => e.toString()).toList() ?? [],
        soilType: json['soil_type'],
        soilAmendments: json['soil_amendments'],
        isIndoor: json['is_indoor'],
        isPetSafe: json['is_pet_safe'],
        isAirPurifying: json['is_air_purifying'],
        careDifficulty: json['care_difficulty'],
        createdAt: parseUtcDateTime(json['created_at']),
        growthBackground: json['growth_background'],
      );

  /// Next date this plant is due for watering — never watered yet counts as
  /// due immediately. Mirrors the same "needs water" rule HomeScreen's
  /// _PlantTile already uses, exposed here for RemindersScreen and the
  /// notification scheduler too.
  DateTime get nextWateringDue =>
      lastWateredAt == null ? DateTime.now() : lastWateredAt!.add(Duration(days: waterFrequencyDays));

  /// Client-side copy used only for the optimistic "mark watered" update in
  /// HomeScreen/PlantDetailScreen — the server write still happens via the
  /// API client, this just keeps the UI responsive while that's in flight.
  Plant copyWith({DateTime? lastWateredAt, String? photoUrl, String? status, String? growthBackground}) => Plant(
        id: id,
        status: status ?? this.status,
        nickname: nickname,
        species: species,
        speciesConfidence: speciesConfidence,
        lightNeeds: lightNeeds,
        waterFrequencyDays: waterFrequencyDays,
        photoUrl: photoUrl ?? this.photoUrl,
        lastWateredAt: lastWateredAt ?? this.lastWateredAt,
        funFacts: funFacts,
        isIndoor: isIndoor,
        isPetSafe: isPetSafe,
        isAirPurifying: isAirPurifying,
        careDifficulty: careDifficulty,
        createdAt: createdAt,
        growthBackground: growthBackground ?? this.growthBackground,
      );
}

/// Mirrors IdentifyData in schemas/ai.py — the raw result of POST
/// /ai/identify, before it's been turned into a saved Plant.
class IdentifyResult {
  final String species;
  final String commonName;
  final String confidence;
  final int waterFrequencyDays;
  final String lightNeeds;
  final String careNote;
  final List<String> funFacts;
  // E-MP001/E-MP002 — see the matching fields on Plant above.
  final List<String> regionalNames;
  final String soilType;
  final String soilAmendments;
  final bool isIndoor;
  final bool isPetSafe;
  final bool isAirPurifying;
  final String careDifficulty;
  // True if this call was charged against the one-time Garden Setup
  // allowance instead of the regular recurring weekly one — see
  // AddPlantScreen, which shows different copy in that case.
  final bool usedGardenSetup;
  // BUG-C003: false means Gemini judged the photo isn't a real, living
  // plant (artificial/plastic plant, a random object, ...) — AddPlantScreen
  // shows funMessage as a playful pop-up instead of the normal "identified!"
  // result in that case, rather than pretending it found a real species.
  final bool isRealPlant;
  final String? funMessage;

  IdentifyResult({
    required this.species,
    required this.commonName,
    required this.confidence,
    required this.waterFrequencyDays,
    required this.lightNeeds,
    required this.careNote,
    required this.funFacts,
    this.regionalNames = const [],
    this.soilType = '',
    this.soilAmendments = '',
    required this.isIndoor,
    required this.isPetSafe,
    required this.isAirPurifying,
    required this.careDifficulty,
    this.usedGardenSetup = false,
    this.isRealPlant = true,
    this.funMessage,
  });

  factory IdentifyResult.fromJson(Map<String, dynamic> json) => IdentifyResult(
        species: json['species'],
        commonName: json['common_name'],
        confidence: json['confidence'],
        waterFrequencyDays: json['water_frequency_days'],
        lightNeeds: json['light_needs'],
        careNote: json['care_note'],
        funFacts: (json['fun_facts'] as List).map((e) => e.toString()).toList(),
        regionalNames: (json['regional_names'] as List?)?.map((e) => e.toString()).toList() ?? [],
        soilType: json['soil_type'] ?? '',
        soilAmendments: json['soil_amendments'] ?? '',
        isIndoor: json['is_indoor'],
        isPetSafe: json['is_pet_safe'],
        isAirPurifying: json['is_air_purifying'],
        careDifficulty: json['care_difficulty'],
        usedGardenSetup: json['used_garden_setup'] ?? false,
        isRealPlant: json['is_real_plant'] ?? true,
        funMessage: json['fun_message'],
      );
}

/// Mirrors DiagnoseData / LatestDiagnosisData in schemas/ai.py.
class DiagnosisResult {
  final String confidence;
  final List<String> likelyCauses;
  final String recommendedAction;
  final String urgency;
  final DateTime? createdAt;

  DiagnosisResult({
    required this.confidence,
    required this.likelyCauses,
    required this.recommendedAction,
    required this.urgency,
    this.createdAt,
  });

  factory DiagnosisResult.fromJson(Map<String, dynamic> json) => DiagnosisResult(
        confidence: json['confidence'],
        likelyCauses: (json['likely_causes'] as List).map((e) => e.toString()).toList(),
        recommendedAction: json['recommended_action'],
        urgency: json['urgency'],
        createdAt: json['created_at'] != null ? parseUtcDateTime(json['created_at']) : null,
      );
}

/// Mirrors WateringScheduleResult in schemas/calculator.py.
class WateringSchedule {
  final int baseIntervalDays;
  final int adjustedIntervalDays;
  final DateTime? nextWateringDate;
  final int recommendedAmountMl;
  final String reasoning;

  WateringSchedule({
    required this.baseIntervalDays,
    required this.adjustedIntervalDays,
    this.nextWateringDate,
    required this.recommendedAmountMl,
    required this.reasoning,
  });

  factory WateringSchedule.fromJson(Map<String, dynamic> json) => WateringSchedule(
        baseIntervalDays: json['base_interval_days'],
        adjustedIntervalDays: json['adjusted_interval_days'],
        nextWateringDate: json['next_watering_date'] != null ? parseUtcDateTime(json['next_watering_date']) : null,
        recommendedAmountMl: json['recommended_amount_ml'],
        reasoning: json['reasoning'],
      );
}

/// Mirrors FertilizerDoseResult in schemas/calculator.py.
class FertilizerDose {
  final bool needed;
  final String? dilutionRatio;
  final int? amountMl;
  final int? frequencyDays;
  final String reasoning;

  FertilizerDose({
    required this.needed,
    this.dilutionRatio,
    this.amountMl,
    this.frequencyDays,
    required this.reasoning,
  });

  factory FertilizerDose.fromJson(Map<String, dynamic> json) => FertilizerDose(
        needed: json['needed'],
        dilutionRatio: json['dilution_ratio'],
        amountMl: json['amount_ml'],
        frequencyDays: json['frequency_days'],
        reasoning: json['reasoning'],
      );
}

/// Mirrors LightFitResult in schemas/calculator.py.
class LightFit {
  final String? plantLightNeeds;
  final String? roomLight;
  final String fit; // ideal | acceptable | poor | unknown
  final String reasoning;

  LightFit({this.plantLightNeeds, this.roomLight, required this.fit, required this.reasoning});

  factory LightFit.fromJson(Map<String, dynamic> json) => LightFit(
        plantLightNeeds: json['plant_light_needs'],
        roomLight: json['room_light'],
        fit: json['fit'],
        reasoning: json['reasoning'],
      );
}

/// Mirrors CalculatorData in schemas/calculator.py — the result of GET
/// /plants/:id/calculators.
class CareCalculators {
  final String plantId;
  final String nickname;
  final String? species;
  final String season;
  final bool locationAware;
  final double? temperatureC;
  final String source; // "ai" | "formula"
  final WateringSchedule watering;
  final FertilizerDose fertilizer;
  final LightFit lightFit;

  CareCalculators({
    required this.plantId,
    required this.nickname,
    this.species,
    required this.season,
    required this.locationAware,
    this.temperatureC,
    required this.source,
    required this.watering,
    required this.fertilizer,
    required this.lightFit,
  });

  factory CareCalculators.fromJson(Map<String, dynamic> json) => CareCalculators(
        plantId: json['plant_id'],
        nickname: json['nickname'],
        species: json['species'],
        season: json['season'],
        locationAware: json['location_aware'] ?? false,
        temperatureC: (json['temperature_c'] as num?)?.toDouble(),
        source: json['source'],
        watering: WateringSchedule.fromJson(json['watering']),
        fertilizer: FertilizerDose.fromJson(json['fertilizer']),
        lightFit: LightFit.fromJson(json['light_fit']),
      );
}

/// Mirrors LocationWeatherPreview in schemas/calculator.py — result of GET
/// /plants/weather-preview.
class LocationWeatherPreview {
  final String season;
  final double? temperatureC;

  LocationWeatherPreview({required this.season, this.temperatureC});

  factory LocationWeatherPreview.fromJson(Map<String, dynamic> json) => LocationWeatherPreview(
        season: json['season'],
        temperatureC: (json['temperature_c'] as num?)?.toDouble(),
      );
}

/// Mirrors FeatureUsage in schemas/entitlement.py — one feature's usage
/// against its current tier's allowance.
class FeatureUsage {
  final int used;
  final int limit; // -1 = unlimited
  final String period; // "lifetime" | "weekly" | "monthly"
  final int remaining; // -1 = unlimited
  final DateTime? resetsAt;

  FeatureUsage({required this.used, required this.limit, required this.period, required this.remaining, this.resetsAt});

  bool get isUnlimited => limit < 0;
  bool get atLimit => !isUnlimited && remaining <= 0;

  factory FeatureUsage.fromJson(Map<String, dynamic> json) => FeatureUsage(
        used: json['used'],
        limit: json['limit'],
        period: json['period'],
        remaining: json['remaining'],
        resetsAt: json['resets_at'] != null ? parseUtcDateTime(json['resets_at']) : null,
      );
}

/// Mirrors GardenSetupData in schemas/entitlement.py — the one-time
/// allowance granted on first upgrade to a paid tier.
class GardenSetup {
  final int total;
  final int used;
  final int remaining;

  GardenSetup({required this.total, required this.used, required this.remaining});

  factory GardenSetup.fromJson(Map<String, dynamic> json) =>
      GardenSetup(total: json['total'], used: json['used'], remaining: json['remaining']);
}

/// Mirrors WishlistData in schemas/entitlement.py — persistent slots for
/// not-yet-owned plants, a separate pool from plantCount/plantLimit.
class WishlistUsage {
  final int count;
  final int limit;
  WishlistUsage({required this.count, required this.limit});
  bool get atLimit => count >= limit;
  factory WishlistUsage.fromJson(Map<String, dynamic> json) => WishlistUsage(count: json['count'], limit: json['limit']);
}

/// Mirrors EntitlementData in schemas/entitlement.py — the rich,
/// tier-aware usage/entitlement payload behind the paywall and the
/// Plan/Usage screen (see settings_subscreens.dart's PlanScreen).
/// Mirrors GrowthMemoryData in schemas/entitlement.py — persistent slots
/// for Growth Journey memories, same PLANT COLLECTION RULES semantics as
/// plantCount/plantLimit (limit=0 means the tier doesn't have the feature
/// at all; limit=-1 means unlimited).
class GrowthMemoryUsage {
  final int count;
  final int limit;
  GrowthMemoryUsage({required this.count, required this.limit});
  bool get isUnlimited => limit < 0;
  bool get isAvailable => isUnlimited || limit > 0;
  bool get atLimit => !isUnlimited && count >= limit;
  factory GrowthMemoryUsage.fromJson(Map<String, dynamic> json) =>
      GrowthMemoryUsage(count: json['count'], limit: json['limit']);
}

class Entitlement {
  final String plan; // "guest" | "plantie" | "green_thumb" | "photosynthesis_phd"
  final String planDisplayName;
  final String subscriptionStatus;
  final DateTime? expiresAt;
  final bool isGuest;
  final int plantCount;
  final int plantLimit;
  final WishlistUsage wishlist;
  final FeatureUsage identification;
  final FeatureUsage careCalculator;
  final FeatureUsage diagnose;
  final GardenSetup gardenSetup;
  final GrowthMemoryUsage growthMemories;
  final String? nextPlan;
  final String? nextPlanDisplayName;

  Entitlement({
    required this.plan,
    required this.planDisplayName,
    required this.subscriptionStatus,
    this.expiresAt,
    required this.isGuest,
    required this.plantCount,
    required this.plantLimit,
    required this.wishlist,
    required this.identification,
    required this.careCalculator,
    required this.diagnose,
    required this.gardenSetup,
    required this.growthMemories,
    this.nextPlan,
    this.nextPlanDisplayName,
  });

  bool get isPaidPlan => plan == 'green_thumb' || plan == 'photosynthesis_phd';

  factory Entitlement.fromJson(Map<String, dynamic> json) => Entitlement(
        plan: json['plan'],
        planDisplayName: json['plan_display_name'],
        subscriptionStatus: json['subscription_status'],
        expiresAt: json['expires_at'] != null ? parseUtcDateTime(json['expires_at']) : null,
        isGuest: json['is_guest'],
        plantCount: json['plant_count'],
        plantLimit: json['plant_limit'],
        wishlist: WishlistUsage.fromJson(json['wishlist']),
        identification: FeatureUsage.fromJson(json['identification']),
        careCalculator: FeatureUsage.fromJson(json['care_calculator']),
        diagnose: FeatureUsage.fromJson(json['diagnose']),
        gardenSetup: GardenSetup.fromJson(json['garden_setup']),
        growthMemories: GrowthMemoryUsage.fromJson(json['growth_memories']),
        nextPlan: json['next_plan'],
        nextPlanDisplayName: json['next_plan_display_name'],
      );
}

/// Mirrors GrowthMemoryItem in schemas/plant.py — one dated, named photo
/// on a plant's Growth Journey timeline.
class GrowthMemory {
  final String id;
  final String plantId;
  final String name;
  final String? note;
  final String photoUrl;
  final DateTime createdAt;

  GrowthMemory({
    required this.id,
    required this.plantId,
    required this.name,
    this.note,
    required this.photoUrl,
    required this.createdAt,
  });

  factory GrowthMemory.fromJson(Map<String, dynamic> json) => GrowthMemory(
        id: json['id'],
        plantId: json['plant_id'],
        name: json['name'],
        note: json['note'],
        photoUrl: json['photo_url'],
        createdAt: parseUtcDateTime(json['created_at']),
      );
}
