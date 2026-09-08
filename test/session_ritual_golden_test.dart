import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/providers/journal_providers.dart';
import 'package:meno/ui/editor_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('journal desktop golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(1280, 800),
      now: DateTime(2026, 9, 1, 10),
    );
    await _seedWriting(harness, tester);
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/daily_journal_desktop.png'),
    );
  });

  testWidgets('journal phone golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(390, 844),
      now: DateTime(2026, 9, 1, 10),
    );
    await _seedWriting(harness, tester);
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/daily_journal_phone.png'),
    );
  });

  testWidgets('entry wheel narrow desktop golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(820, 700),
      now: DateTime(2026, 9, 1, 10),
    );
    await _seedWriting(harness, tester);
    final controller = harness.container.read(
      journalControllerProvider.notifier,
    );
    await controller.addEntry(now: DateTime(2026, 9, 1, 12, 30));
    controller.updateEntry(
      title: 'A thought at lunch',
      content: 'The slower route made room for a better conversation.',
      now: DateTime(2026, 9, 1, 12, 30),
    );
    await controller.saveCurrentEntry();
    await controller.addEntry(now: DateTime(2026, 9, 1, 16, 45));
    controller.updateEntry(
      title: 'Late afternoon',
      content: 'A quiet idea worth returning to tomorrow.',
      now: DateTime(2026, 9, 1, 16, 45),
    );
    await controller.saveCurrentEntry();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/entry_wheel_narrow_desktop.png'),
    );
  });

  testWidgets('binder days golden', (tester) async {
    final harness = await _pumpCompletedBinder(
      tester,
      size: const Size(1180, 780),
    );
    final rail = tester.widget<Listener>(find.byKey(const Key('binder-rail')));
    rail.onPointerSignal!(const PointerScrollEvent(scrollDelta: Offset(0, 48)));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/binder_days_desktop.png'),
    );
    expect(
      harness.container.read(journalControllerProvider).phase,
      AppPhase.binder,
    );
  });

  testWidgets('binder weeks reduced motion golden', (tester) async {
    final harness = await _pumpCompletedBinder(
      tester,
      size: const Size(1000, 700),
      disableAnimations: true,
    );
    harness.container
        .read(binderControllerProvider.notifier)
        .setZoom(BinderZoom.weeks);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/binder_weeks_reduced_motion.png'),
    );
  });

  testWidgets('mood large text and high contrast golden', (tester) async {
    await _pumpGolden(
      tester,
      size: const Size(900, 800),
      now: DateTime(2026, 9, 1, 18),
      highContrast: true,
      textScaler: const TextScaler.linear(1.35),
    );
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/mood_large_text_high_contrast.png'),
    );
  });

  testWidgets('journal large text and high contrast golden', (tester) async {
    final harness = await _pumpGolden(
      tester,
      size: const Size(900, 800),
      now: DateTime(2026, 9, 1, 10),
      highContrast: true,
      textScaler: const TextScaler.linear(1.35),
    );
    await _seedWriting(harness, tester);
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/journal_large_text_high_contrast.png'),
    );
  });
}

Future<void> _seedWriting(_GoldenHarness harness, WidgetTester tester) async {
  final controller = harness.container.read(journalControllerProvider.notifier);
  controller.updateEntry(
    title: '',
    content:
        'Today felt unhurried. I noticed how much easier it was to listen when I stopped planning my next sentence.',
  );
  controller.updateGratitude('The late-afternoon rain and a long cup of tea.');
  await controller.saveCurrentEntry();
  await controller.saveGratitude();
  await tester.pumpAndSettle();
}

Future<_GoldenHarness> _pumpCompletedBinder(
  WidgetTester tester, {
  required Size size,
  bool disableAnimations = false,
}) async {
  final database = FakeDatabaseService();
  final now = DateTime(2026, 9, 1, 20);
  for (var offset = 0; offset < 12; offset++) {
    final date = now.subtract(Duration(days: offset * 2));
    final key = localDateKey(date);
    await database.saveDayEntry(
      DayEntry.empty(
        dateKey: key,
        type: DayEntryType.daily,
        now: date,
      ).copyWith(
        content: offset == 0
            ? 'Today felt unhurried. I made room to listen and came home lighter.'
            : 'A small record of the day, kept without trying to solve it.',
      ),
    );
    await database.saveDay(
      (await database.journalDay(
        key,
      ))!.copyWith(gratitude: offset.isEven ? 'A quiet walk home.' : ''),
    );
    await database.saveCheckIn(
      DailyCheckIn.forDate(
        dateKey: key,
        moodAngle: .15 + offset * .12,
        moodIntensity: .45 + offset * .08,
        now: date,
      ),
    );
  }
  return _pumpGolden(
    tester,
    size: size,
    now: now,
    database: database,
    disableAnimations: disableAnimations,
  );
}

Future<_GoldenHarness> _pumpGolden(
  WidgetTester tester, {
  required Size size,
  required DateTime now,
  FakeDatabaseService? database,
  bool disableAnimations = false,
  bool highContrast = false,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final db = database ?? FakeDatabaseService();
  final container = ProviderContainer(
    overrides: [databaseServiceProvider.overrideWithValue(db)],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1,
            disableAnimations: disableAnimations,
            highContrast: highContrast,
            textScaler: textScaler,
          ),
          child: const EditorScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await container.read(journalControllerProvider.notifier).initialize(now: now);
  await tester.pumpAndSettle();
  return _GoldenHarness(container);
}

class _GoldenHarness {
  const _GoldenHarness(this.container);

  final ProviderContainer container;
}
