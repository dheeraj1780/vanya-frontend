import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: AppColors.bgOf(context),
      body: Stack(
        children: [
          // Full-bleed leaf photo behind the status bar — the content card
          // below overlaps its bottom edge for a layered, editorial feel
          // rather than a flat icon-and-text onboarding screen.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/images/green_leaves.jpg', fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black26, Colors.transparent, AppColors.bgOf(context)],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('Never lose\na plant again', textAlign: TextAlign.center, style: AppTypography.display(AppColors.primary)),
                          const SizedBox(height: 14),
                          Text(
                            'Snap a photo, get care instructions, and know exactly when to water.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyLarge(AppColors.textSecondaryOf(context)),
                          ),
                          const SizedBox(height: 28),
                          PrimaryButton(label: 'Get started', onPressed: () => context.read<AppState>().goTo('permissions')),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
