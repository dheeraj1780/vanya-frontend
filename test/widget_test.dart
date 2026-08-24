// Basic smoke test — verifies the app boots to the animated Splash screen
// (the presentation gate main.dart shows first, see PlantCompanionApp),
// then, once that finishes, reaches the Welcome screen — the one screen
// reachable with no backend or Firebase calls actually succeeding in a
// test environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:plant_companion/app_state.dart';
import 'package:plant_companion/main.dart';
import 'package:plant_companion/screens/splash_screen.dart';
import 'package:plant_companion/screens/welcome_screen.dart';

void main() {
  testWidgets('Boots to Splash, then the Welcome screen with no stored session', (WidgetTester tester) async {
    final appState = AppState(); // screen defaults to 'welcome' pre-bootstrap()

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const PlantCompanionApp(),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);

    // Let the splash's letter/dash/exit animation sequence run to
    // completion. Manual incremental pumps, not pumpAndSettle — the
    // sequence alternates AnimationController.forward() with real
    // Future.delayed gaps, and pumpAndSettle stops the moment no frame is
    // scheduled, which happens during those gaps before the next phase
    // has even started.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
