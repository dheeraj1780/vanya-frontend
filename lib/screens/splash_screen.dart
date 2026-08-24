import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

/// Cold-start intro: plays the bundled VANYA intro video full-screen, then
/// hands off to the real app. Falls back to a letter-by-letter "VANYA"
/// animation (built before the video existed) if the video ever fails to
/// load/decode — so a bad asset can't strand the app on a frozen splash.
/// Shown once per launch by main.dart (a presentation gate in front of
/// RootRouter, not part of AppState's own screen routing).
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset('assets/videos/vanya_intro.mp4');
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      setState(() => _controller = controller);
      await controller.play();
    } catch (e) {
      debugPrint('Intro video failed to load, falling back to the letter animation: $e');
      controller.dispose();
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || _done) return;
    final value = controller.value;
    if (value.isInitialized && !value.isPlaying && value.position >= value.duration) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videoFailed) {
      return _LetterFallbackSplash(onDone: widget.onDone);
    }

    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          // Tap-to-skip — a full-screen video intro shouldn't be a wall
          // between the user and the app if they've already seen it.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: _finish,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('Skip', style: AppTypography.bodyStrong(Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The original entrance animation, kept as a fallback for when the video
/// can't play: background fades in over the leaf photo, "VANYA" slides in
/// letter by letter, a dash flourishes underneath with a small leaf riding
/// its edge, then fades into the app.
class _LetterFallbackSplash extends StatefulWidget {
  final VoidCallback onDone;
  const _LetterFallbackSplash({required this.onDone});

  @override
  State<_LetterFallbackSplash> createState() => _LetterFallbackSplashState();
}

class _LetterFallbackSplashState extends State<_LetterFallbackSplash> with TickerProviderStateMixin {
  static const _word = 'VANYA';

  late final AnimationController _backgroundController;
  late final AnimationController _lettersController;
  late final AnimationController _dashController;
  late final AnimationController _exitController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _lettersController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _dashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _exitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _runSequence();
  }

  Future<void> _runSequence() async {
    await _backgroundController.forward();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _lettersController.forward();
    if (!mounted) return;
    await _dashController.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _exitController.forward();
    widget.onDone();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _lettersController.dispose();
    _dashController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  double _letterProgress(int index) {
    const stagger = 0.12;
    final start = index * stagger;
    final end = (start + 0.55).clamp(0.0, 1.0);
    final raw = ((_lettersController.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_backgroundController, _lettersController, _dashController, _exitController]),
      builder: (context, _) {
        return Opacity(
          opacity: 1 - _exitController.value,
          child: Scaffold(
            backgroundColor: AppColors.primaryDark,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: _backgroundController.value,
                  child: Image.asset('assets/images/green_leaves.jpg', fit: BoxFit.cover),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primaryDark.withValues(alpha: 0.75 * _backgroundController.value),
                        AppColors.primaryDark.withValues(alpha: 0.92 * _backgroundController.value),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < _word.length; i++) _buildLetter(_word[i], i),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDash(),
                      const SizedBox(height: 18),
                      Opacity(
                        opacity: _dashController.value,
                        child: Text('grow something beautiful', style: AppTypography.caption(Colors.white70).copyWith(letterSpacing: 2)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLetter(String letter, int index) {
    final t = _letterProgress(index);
    return Transform.translate(
      offset: Offset(0, (1 - t) * 26),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Text(letter, style: AppTypography.display(Colors.white).copyWith(fontSize: 46, letterSpacing: 4)),
      ),
    );
  }

  Widget _buildDash() {
    const maxWidth = 130.0;
    final width = maxWidth * _dashController.value;
    return SizedBox(
      width: maxWidth,
      height: 18,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(height: 2.5, width: width, decoration: BoxDecoration(color: AppColors.sage, borderRadius: BorderRadius.circular(2))),
          Positioned(
            left: (width - 8).clamp(0.0, maxWidth),
            child: Opacity(
              opacity: _dashController.value > 0.05 ? 1 : 0,
              child: const Icon(Icons.eco, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
