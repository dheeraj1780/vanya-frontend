import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

class DiagnosisResultScreen extends StatelessWidget {
  const DiagnosisResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final result = appState.diagnosisResult;
    final plant = appState.selectedPlant;
    if (result == null) return const SizedBox.shrink();

    final urgencyColor = result.urgency == 'low' ? AppColors.primary : AppColors.accent;
    final urgencyLabel = result.urgency == 'low'
        ? 'Low urgency'
        : result.urgency == 'high'
            ? 'Act soon'
            : 'Worth checking';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: appState.returnTo)),
        title: Text(plant?.nickname ?? 'Diagnosis'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 12, color: urgencyColor),
                const SizedBox(width: 5),
                Text(urgencyLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: urgencyColor)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _Label('Confidence'),
          Text(result.confidence, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const _Label('Likely causes'),
          ...result.likelyCauses.map((c) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('•  $c', style: const TextStyle(fontSize: 13)),
              )),
          const SizedBox(height: 12),
          const _Label('Recommended action'),
          Text(result.recommendedAction, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 18),
          Text(
            'This is a best-effort AI read of your photos — if symptoms persist, a local nursery can give you a hands-on second opinion.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Got it', icon: Icons.check, onPressed: () => appState.goBack(fallback: appState.returnTo)),
        ],
      ),
    );
  }
}

/// E-MP001/E-MP002: this used to be just a bare bullet list of fun_facts —
/// "Facts are quite less" and no name beyond the botanical one. Now leads
/// with the names people actually call this plant (including Indian
/// household/vernacular names, since that's who most of this app's users
/// are — see ai_provider.IDENTIFY_PROMPT) and a soil recommendation, before
/// the facts list.
class PlantFactsScreen extends StatelessWidget {
  const PlantFactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final plant = appState.selectedPlant;
    if (plant == null) return const SizedBox.shrink();

    final hasNothing = plant.funFacts.isEmpty && plant.regionalNames.isEmpty && (plant.soilType?.isEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => appState.goBack(fallback: 'plantDetail')),
        title: Text('About your ${plant.nickname}'),
      ),
      body: hasNothing
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [Text('No facts saved for this plant yet.', style: Theme.of(context).textTheme.bodyMedium)],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (plant.species != null) ...[
                  _Label('Botanical name'),
                  const SizedBox(height: 4),
                  Text(plant.species!, style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 16),
                ],
                if (plant.regionalNames.isNotEmpty) ...[
                  _Label('Also known as'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: plant.regionalNames
                        .map((name) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTintPairOf(context).$1,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryTintPairOf(context).$2),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                if ((plant.soilType?.isNotEmpty ?? false)) ...[
                  _Label('Soil'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Deliberately earth (brown), not sage — the one
                        // place in this screen the content is literally
                        // about soil. See AppColors.earth's docstring.
                        Icon(Icons.grass, size: 15, color: AppColors.earthTintPairOf(context).$2),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The named soil type (e.g. "Red soil", "Sandy loam") leads,
                              // bold — the amendments are a supporting suggestion below it.
                              Text(plant.soilType!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.4)),
                              if (plant.soilAmendments?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 3),
                                Text(plant.soilAmendments!, style: const TextStyle(fontSize: 13, height: 1.5)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (plant.funFacts.isNotEmpty) ...[
                  _Label('Fun facts'),
                  const SizedBox(height: 6),
                  for (final fact in plant.funFacts)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_awesome, size: 15, color: AppColors.accent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(fact, style: const TextStyle(fontSize: 13, height: 1.5))),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: TextStyle(fontSize: 10.5, color: AppColors.textSecondaryOf(context), letterSpacing: 0.4));
}
