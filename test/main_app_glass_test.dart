import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meno/main.dart';
import 'package:meno/providers/journal_providers.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/services/window_appearance_service.dart';
import 'package:meno/ui/theme_primitives.dart';

import 'support/session_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('meno/window_appearance_app_test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('restored glass mode is applied to the native window', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final database = FakeDatabaseService();
    await database.saveSetting(DatabaseService.glassModeSettingKey, 'true');
    final service = WindowAppearanceService(channel: channel, isMacOS: true);
    final container = ProviderContainer(
      overrides: [
        databaseServiceProvider.overrideWithValue(database),
        windowAppearanceServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MenoApp()),
    );
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.arguments), [false, true]);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .extension<MenoSurfaces>(),
      const MenoSurfaces.glass(),
    );

    await container
        .read(journalControllerProvider.notifier)
        .setGlassModeEnabled(false);
    await tester.pump();
    expect(calls.last.arguments, isFalse);
  });

  testWidgets(
    'unsupported platforms keep opaque surfaces and skip the bridge',
    (tester) async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            called = true;
            return null;
          });
      final database = FakeDatabaseService();
      await database.saveSetting(DatabaseService.glassModeSettingKey, 'true');
      final service = WindowAppearanceService(channel: channel, isMacOS: false);
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(database),
          windowAppearanceServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MenoApp()),
      );
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .extension<MenoSurfaces>(),
        const MenoSurfaces.opaque(),
      );
    },
  );
}
