import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client2/app.dart';
import 'package:client2/config/mode_config.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ModeConfig unit tests
  // ---------------------------------------------------------------------------
  group('ModeConfig', () {
    test('defaults to prod when no --dart-define is supplied', () {
      // During `flutter test` without --dart-define=EYED_MODE, the value is
      // the defaultValue ('prod').
      expect(ModeConfig.mode, 'prod');
      expect(ModeConfig.isProd, isTrue);
      expect(ModeConfig.isDev, isFalse);
      expect(ModeConfig.isTest, isFalse);
      expect(ModeConfig.showDevTools, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget smoke test — runs in the default prod test environment
  // ---------------------------------------------------------------------------
  group('EyeDApp (prod mode — default test env)', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: EyeDApp()),
      );
      await tester.pump();
      expect(find.text('EyeD'), findsOneWidget);
    });

    testWidgets('DEV badge is absent in prod mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: EyeDApp()),
      );
      await tester.pump();

      // ModeConfig.showDevTools == false → _DevBadge never built
      // 'DEV' text must not appear anywhere in the tree
      expect(find.text('DEV'), findsNothing);
    });

    testWidgets('FHE toggle chip is absent in prod mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: EyeDApp()),
      );
      await tester.pump();

      // ActionChip for FHE is not in the tree in prod
      expect(find.text('FHE On'),  findsNothing);
      expect(find.text('FHE Off'), findsNothing);
    });
  });
}
