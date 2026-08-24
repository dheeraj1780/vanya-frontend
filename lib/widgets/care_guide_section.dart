import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Structured practical care instructions, built from the plant's own
/// stored fields (water_frequency_days, light_needs, care_difficulty,
/// is_pet_safe, is_air_purifying) — not the AI's free-text trivia, which
/// is what the separate "Plant facts" screen already shows in full.
/// Genuinely different content, not a relabeled duplicate.
class CareGuideSection extends StatelessWidget {
  final Plant plant;
  const CareGuideSection({super.key, required this.plant});

  String get _wateringTip {
    final days = plant.waterFrequencyDays;
    if (days <= 4) return 'Check the soil every couple of days — this one dries out fast and doesn\'t like to sit thirsty.';
    if (days <= 10) return 'Water once the top inch or two of soil feels dry to the touch, then let it drain fully.';
    return 'Let the soil dry out well between waterings — this one is more at risk from overwatering than underwatering.';
  }

  String get _lightTip {
    final needs = (plant.lightNeeds ?? '').toLowerCase();
    if (needs.contains('low')) return 'Tolerates low light well — a spot a few feet from any window is fine.';
    if (needs.contains('direct') || needs.contains('full sun')) return 'Give it your brightest spot — several hours of direct sun daily.';
    if (needs.contains('bright') || needs.contains('indirect')) return 'Bright, indirect light — near a window but out of direct midday sun.';
    return 'Light needs weren\'t captured for this plant — moderate indirect light is a safe default.';
  }

  (String, String) get _difficultyTip {
    switch (plant.careDifficulty) {
      case 'easy':
        return ('Easy', 'Forgiving of missed waterings and less-than-ideal light — a good one to not worry over.');
      case 'hard':
        return ('Hands-on', 'Fussier about consistency — try to keep watering and light on a steady schedule.');
      default:
        return ('Moderate', 'Reasonably adaptable, but happiest with a fairly consistent routine.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (difficultyLabel, difficultyTip) = _difficultyTip;
    final items = [
      _GuideItem(icon: Icons.water_drop_outlined, title: 'Watering', tip: _wateringTip),
      _GuideItem(icon: Icons.wb_sunny_outlined, title: 'Light', tip: _lightTip),
      _GuideItem(icon: Icons.auto_graph_outlined, title: '$difficultyLabel care', tip: difficultyTip),
      if (plant.isPetSafe != null || plant.isAirPurifying != null)
        _GuideItem(
          icon: Icons.shield_outlined,
          title: 'Safety',
          tip: [
            if (plant.isPetSafe == true) 'Non-toxic to cats and dogs.' else if (plant.isPetSafe == false) 'Keep away from pets — toxic if ingested.',
            if (plant.isAirPurifying == true) 'Recognized for measurable air-purifying effect.',
          ].where((s) => s.isNotEmpty).join(' '),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CARE GUIDE', style: AppTypography.eyebrow(AppColors.sage)),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.borderOf(context))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AppColors.primaryTintPairOf(context).$1, shape: BoxShape.circle),
                    child: Icon(item.icon, size: 15, color: AppColors.primaryTintPairOf(context).$2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: AppTypography.bodyStrong(AppColors.textOf(context))),
                        const SizedBox(height: 2),
                        Text(item.tip, style: AppTypography.body(AppColors.textSecondaryOf(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _GuideItem {
  final IconData icon;
  final String title;
  final String tip;
  _GuideItem({required this.icon, required this.title, required this.tip});
}
