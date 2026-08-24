import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One place that decides how a plant photo renders — real photo when
/// there is one, a soft leafy gradient placeholder (never a broken-image
/// icon or blank box) when there isn't. Used by PlantCard, Plant Detail's
/// hero, and the My Plants grid so every plant image looks consistent.
class PlantImage extends StatelessWidget {
  final String? url;
  final double? borderRadius;
  final BoxFit fit;

  const PlantImage({super.key, required this.url, this.borderRadius, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? AppRadius.lg);
    return ClipRRect(
      borderRadius: radius,
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => const _Placeholder(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const _Placeholder(loading: true),
            )
          : const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool loading;
  const _Placeholder({this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.placeholderGradientOf(context)),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.primary)),
            )
          : const Icon(Icons.eco_outlined, color: AppColors.primary, size: 30),
    );
  }
}
