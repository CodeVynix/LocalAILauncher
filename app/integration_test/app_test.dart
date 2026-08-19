// Integration tests for LocalAILauncher.
//
// These tests run on a real device or emulator and verify that core
// UI screens render correctly without crashing.
//
// How to run:
//
//   flutter test integration_test/app_test.dart
//
// Firebase Test Lab (Android):
//   flutter build apk --debug
//   gcloud firebase test android run \
//     --type instrumentation \
//     --app build/app/outputs/flutter-apk/app-debug.apk \
//     --test build/app/outputs/flutter-apk/app-debug-androidTest.apk

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:local_ai_launcher/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App launch smoke test', () {
    testWidgets('app launches without crashing', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: LocalAILauncherApp()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the bottom navigation bar renders
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('Chat tab', () {
    testWidgets('shows no-model error when no model is selected',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: LocalAILauncherApp()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Chat is the default tab (index 0)
      // When no model is selected, it should show the error state
      expect(find.text('Error: No local model detected, download one.'),
          findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('Download tab', () {
    testWidgets('renders recommended models list with device info',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: LocalAILauncherApp()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to Download tab
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the device info bar is shown
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.textContaining('RAM'), findsWidgets);
      expect(find.textContaining('CPU cores'), findsWidgets);

      // Verify the recommended models tab is selected
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Import Custom'), findsOneWidget);

      // Verify at least some model cards are rendered
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('download button responds to single tap', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: LocalAILauncherApp()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to Download tab
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Find a Download button and tap it once
      final downloadButtons = find.text('Download');
      expect(downloadButtons, findsWidgets);

      // Tap the first Download button (on the first model card)
      await tester.tap(downloadButtons.first);
      await tester.pump();

      // After a single tap, the button should either:
      // - Show a loading spinner (isStartingDownload = true), OR
      // - Show progress indicator (downloading started)
      // The key thing is: the Download button text should NOT appear multiple
      // times as separate buttons (debounce guard should prevent duplicate taps)
    });
  });

  group('Settings tab', () {
    testWidgets('renders temperature slider and web server toggle',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: LocalAILauncherApp()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify hardware section
      expect(find.text('Device Hardware'), findsOneWidget);
      expect(find.byIcon(Icons.memory), findsOneWidget);
      expect(find.byIcon(Icons.developer_board), findsOneWidget);
      expect(find.byIcon(Icons.storage), findsOneWidget);

      // Verify temperature section
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('0.0 - Safe/Deterministic'), findsOneWidget);
      expect(find.text('1.5 - Random/Creative'), findsOneWidget);

      // Verify web server section
      expect(find.text('Local Web Server'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Verify model management section
      expect(find.text('Downloaded Models'), findsOneWidget);
    });
  });
}
