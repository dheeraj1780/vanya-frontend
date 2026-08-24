import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A short, celebratory burst of leaf icons floating up and fading out —
/// for satisfying completion moments (marking a plant watered, adding one
/// to My Plants). Self-inserts into the nearest Overlay and removes itself
/// when done; call sites just fire-and-forget `LeafBurst.play(context)`.
///
/// Deliberately built on core Flutter (AnimationController + Positioned),
/// not a confetti/particles package — one less native dependency in a
/// project that's already had enough Gradle/plugin friction this session.
class LeafBurst {
  static void play(BuildContext context, {int count = 12}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _LeafBurstOverlay(count: count, onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _LeafBurstOverlay extends StatefulWidget {
  final int count;
  final VoidCallback onDone;
  const _LeafBurstOverlay({required this.count, required this.onDone});

  @override
  State<_LeafBurstOverlay> createState() => _LeafBurstOverlayState();
}

class _LeafBurstOverlayState extends State<_LeafBurstOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_LeafSpec> _leaves;

  static const _icons = [Icons.eco, Icons.eco_outlined, Icons.spa_outlined];
  static const _colors = [AppColors.primary, AppColors.sage, AppColors.accent];

  @override
  void initState() {
    super.initState();
    final random = Random();
    _leaves = List.generate(widget.count, (_) {
      return _LeafSpec(
        startX: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        drift: (random.nextDouble() - 0.5) * 70,
        size: 16 + random.nextDouble() * 14,
        spin: (random.nextDouble() - 0.5) * 3,
        icon: _icons[random.nextInt(_icons.length)],
        color: _colors[random.nextInt(_colors.length)],
      );
    });
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(children: [for (final leaf in _leaves) _buildLeaf(leaf, size)]),
      ),
    );
  }

  Widget _buildLeaf(_LeafSpec leaf, Size screenSize) {
    final raw = ((_controller.value - leaf.delay) / (1 - leaf.delay)).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(raw);
    final startY = screenSize.height * 0.68;
    final travel = screenSize.height * 0.4;
    final top = startY - travel * eased;
    final left = (leaf.startX * screenSize.width + leaf.drift * eased).clamp(0.0, screenSize.width - leaf.size);
    final fadeIn = (raw / 0.15).clamp(0.0, 1.0);
    final fadeOut = 1 - ((raw - 0.6).clamp(0.0, 0.4) / 0.4);
    final opacity = min(fadeIn, fadeOut).clamp(0.0, 1.0);

    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(angle: leaf.spin * eased * pi, child: Icon(leaf.icon, size: leaf.size, color: leaf.color)),
      ),
    );
  }
}

class _LeafSpec {
  final double startX;
  final double delay;
  final double drift;
  final double size;
  final double spin;
  final IconData icon;
  final Color color;
  _LeafSpec({required this.startX, required this.delay, required this.drift, required this.size, required this.spin, required this.icon, required this.color});
}
