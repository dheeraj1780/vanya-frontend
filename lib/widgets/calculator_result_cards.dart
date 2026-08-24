import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

/// Three purpose-built result cards for Care Calculators — previously one
/// generic `_ResultCard` template reused three times with just an icon/color
/// swapped. Each of these now has its own layout suited to what it's
/// actually showing: a progress-to-due-date bar for watering, a "recipe"
/// style stat for fertilizer dilution, a 4-segment light gauge for fit.

class WateringResultCard extends StatelessWidget {
  final WateringSchedule watering;
  const WateringResultCard({super.key, required this.watering});

  @override
  Widget build(BuildContext context) {
    final due = watering.nextWateringDate;
    double? progress;
    String? dueLabel;
    if (due != null) {
      final hoursLeft = due.difference(DateTime.now()).inHours;
      final daysLeft = hoursLeft / 24;
      progress = (1 - (daysLeft / watering.adjustedIntervalDays)).clamp(0.0, 1.0);
      dueLabel = daysLeft <= 0 ? 'Due now' : daysLeft < 1 ? 'Due today' : 'Due in ${daysLeft.ceil()} day${daysLeft.ceil() == 1 ? '' : 's'}';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryDark, AppColors.primary]),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: const Icon(Icons.water_drop, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WATERING', style: AppTypography.eyebrow(Colors.white70)),
                    Text('Every ${watering.adjustedIntervalDays}d', style: AppTypography.h1(Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.2), color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(dueLabel!, style: AppTypography.caption(Colors.white70)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.opacity, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text('~${watering.recommendedAmountMl} ml per watering', style: AppTypography.bodyStrong(Colors.white)),
            ],
          ),
          const SizedBox(height: 10),
          Text(watering.reasoning, style: AppTypography.body(Colors.white70)),
        ],
      ),
    );
  }
}

class FertilizerResultCard extends StatelessWidget {
  final FertilizerDose fertilizer;
  const FertilizerResultCard({super.key, required this.fertilizer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.sageTintPairOf(context).$1, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.sage.withValues(alpha: 0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.surfaceOf(context), shape: BoxShape.circle),
                child: const Icon(Icons.spa_outlined, color: AppColors.sage, size: 18),
              ),
              const SizedBox(width: 10),
              Text('FERTILIZER', style: AppTypography.eyebrow(AppColors.sage)),
            ],
          ),
          const SizedBox(height: 14),
          if (fertilizer.needed) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fertilizer.dilutionRatio ?? '', style: AppTypography.display(AppColors.textOf(context)).copyWith(fontSize: 26)),
                const SizedBox(width: 8),
                // "fertilizer : water", not the old vague "diluted feed" —
                // e.g. "1:10" + this reads as "1:10 fertilizer : water"
                // (1 part fertilizer to 10 parts water), which was
                // genuinely unclear before. reasoning below spells out the
                // rest (assumes a standard balanced liquid fertilizer, and
                // the ml amount is the mixed solution, not raw concentrate).
                Text('fertilizer : water', style: AppTypography.body(AppColors.textSecondaryOf(context))),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                StatusBadge(label: 'Every ${fertilizer.frequencyDays}d', tone: StatusTone.neutral, icon: Icons.repeat),
                if (fertilizer.amountMl != null) StatusBadge(label: '~${fertilizer.amountMl} ml', tone: StatusTone.neutral, icon: Icons.opacity),
              ],
            ),
          ] else
            Row(
              children: [
                const Icon(Icons.nightlight_outlined, size: 18, color: AppColors.sage),
                const SizedBox(width: 8),
                Text('Resting this season', style: AppTypography.h3(AppColors.textOf(context))),
              ],
            ),
          const SizedBox(height: 10),
          Text(fertilizer.reasoning, style: AppTypography.body(AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

class LightFitResultCard extends StatelessWidget {
  final LightFit lightFit;
  const LightFitResultCard({super.key, required this.lightFit});

  static const _levels = ['low', 'medium', 'bright', 'direct'];
  static const _levelLabels = ['Low', 'Medium', 'Bright', 'Direct'];

  (String, StatusTone) get _fitPresentation => switch (lightFit.fit) {
        'ideal' => ('Ideal match', StatusTone.healthy),
        'acceptable' => ('Acceptable match', StatusTone.neutral),
        'poor' => ('Poor match', StatusTone.attention),
        _ => ('Not enough info', StatusTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final (fitLabel, tone) = _fitPresentation;
    final activeIndex = _levels.indexOf(lightFit.roomLight ?? '');
    final barColor = tone == StatusTone.attention ? AppColors.accent : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.borderOf(context))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Builder(builder: (context) {
                final (tint, tintFg) = AppColors.accentTintPairOf(context);
                return Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  child: Icon(Icons.wb_sunny_outlined, color: tintFg, size: 18),
                );
              }),
              const SizedBox(width: 10),
              Expanded(child: Text('LIGHT FIT', style: AppTypography.eyebrow(AppColors.textSecondaryOf(context)))),
              StatusBadge(label: fitLabel, tone: tone),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 0; i < _levels.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == activeIndex ? barColor : AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (int i = 0; i < _levelLabels.length; i++)
                Expanded(
                  child: Text(
                    _levelLabels[i],
                    textAlign: i == 0 ? TextAlign.start : (i == _levelLabels.length - 1 ? TextAlign.end : TextAlign.center),
                    style: AppTypography.caption(i == activeIndex ? barColor : AppColors.textSecondaryOf(context)).copyWith(fontWeight: i == activeIndex ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(lightFit.reasoning, style: AppTypography.body(AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}
