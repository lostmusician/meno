import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/providers/journal_providers.dart';
import 'package:meno/services/bible_service.dart';
import 'package:meno/services/database_service.dart';
import 'package:meno/ui/editor_screen.dart';
import 'package:meno/ui/scripture_screen.dart';

import 'support/session_test_doubles.dart';

void main() {
  testWidgets('discovery searches tags and exposes a bounded graph', (
    tester,
  ) async {
    final harness = await _pumpCompletedApp(tester);
    final entry = harness.daily;
    final tag = await harness.database.ensureTag('Work');
    await harness.database.attachTag(
      entryId: entry.id,
      tag: tag,
      source: EntryTagSource.manual,
    );
    await harness.container
        .read(binderControllerProvider.notifier)
        .refresh(anchorDateKey: entry.dateKey);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('binder-discovery')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('journal-search')), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
    expect(find.textContaining('A thoughtful project launch'), findsWidgets);

    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connections-graph')), findsOneWidget);
  });

  testWidgets(
    'Quiet Time logging creates entries and attaches licensed Scripture',
    (tester) async {
      final harness = await _pumpCompletedApp(
        tester,
        quietTimeLogging: true,
        platform: TargetPlatform.macOS,
      );

      await tester.tap(find.byKey(const Key('edit-journal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-entry')), findsOneWidget);
      expect(find.byKey(const Key('open-scripture')), findsNothing);

      await tester.tap(find.byKey(const Key('new-entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-quiet-time')));
      await tester.pumpAndSettle();
      expect(
        harness.container
            .read(journalControllerProvider)
            .selectedEntry
            ?.purpose,
        EntryPurpose.quietTime,
      );
      expect(find.text('Observation'), findsOneWidget);
      expect(find.byKey(const Key('gratitude-editor')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('attach-scripture')));
      await tester.tap(find.byKey(const Key('attach-scripture')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-scripture-panel')), findsOneWidget);
      expect(find.byKey(const Key('scripture-verse-list')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scripture-verse-GEN.1.2')),
        findsOneWidget,
      );
      final journalTextBefore = tester
          .widget<TextField>(find.byKey(const Key('journal-editor')))
          .controller!
          .text;
      await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add-scripture-to-journal')));
      await tester.pumpAndSettle();

      final entryId = harness.container
          .read(journalControllerProvider)
          .selectedEntryId!;
      final references = await harness.database.scripturesForEntry(entryId);
      expect(references.single.reference, 'Genesis 1:1');
      expect(find.text('Genesis 1:1 · NIV'), findsOneWidget);
      expect(find.byKey(const Key('linked-scripture-text')), findsOneWidget);
      expect(find.byKey(const Key('scripture-verse-list')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('journal-editor')))
            .controller!
            .text,
        journalTextBefore,
      );
    },
  );

  testWidgets('Scripture reader selects a contiguous verse range', (
    tester,
  ) async {
    ScriptureSelection? addedSelection;
    final container = ProviderContainer(
      overrides: [
        youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ScriptureWorkspace(
              onAdd: (selection) async => addedSelection = selection,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.1')));
    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.2')));
    await tester.pump();

    expect(find.text('Genesis 1:1–2'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('add-scripture-to-journal')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('add-scripture-to-journal')));
    await tester.pump();
    expect(addedSelection?.passageId, 'GEN.1.1-GEN.1.2');
    expect(addedSelection?.reference, 'Genesis 1:1–2');

    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.1')));
    await tester.pump();
    expect(find.text('Genesis 1:1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.1')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('add-scripture-to-journal')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.2')));
    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.1')));
    await tester.pump();
    expect(find.text('Genesis 1:1–2'), findsOneWidget);
  });

  testWidgets('mobile Scripture sheet closes after adding a linked verse', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await _pumpCompletedApp(
      tester,
      quietTimeLogging: true,
      platform: TargetPlatform.iOS,
    );

    await tester.tap(find.byKey(const Key('edit-journal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-quiet-time')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('attach-scripture')));
    await tester.tap(find.byKey(const Key('attach-scripture')));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scripture-verse-GEN.1.2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-scripture-to-journal')));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    final entryId = harness.container
        .read(journalControllerProvider)
        .selectedEntryId!;
    expect(await harness.database.scripturesForEntry(entryId), hasLength(1));
  });

  testWidgets(
    'mobile Scripture controls dock, collapse, and expand on scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer(
        overrides: [
          youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            themeMode: ThemeMode.light,
            home: ScriptureWorkspace(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scripture-drag-handle')), findsOneWidget);
      expect(
        find.byKey(const Key('scripture-expanded-pickers')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scripture-collapsed-picker')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('scripture-book-picker'))).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const Key('scripture-verse-list')))
              .dy,
        ),
      );

      await tester.tap(find.byKey(const Key('scripture-book-picker')));
      await tester.pumpAndSettle();
      final menuItem = find.widgetWithText(MenuItemButton, 'Genesis');
      expect(menuItem, findsOneWidget);
      expect(
        tester.getBottomRight(menuItem).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('scripture-book-picker'))).dy,
        ),
      );
      await tester.tapAt(const Offset(380, 60));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('scripture-verse-list')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scripture-collapsed-picker')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scripture-expanded-pickers')), findsNothing);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const Key('scripture-top-fade')),
            )
            .opacity,
        1,
      );

      await tester.tap(find.byKey(const Key('scripture-collapsed-picker')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scripture-expanded-pickers')),
        findsOneWidget,
      );
    },
  );

  testWidgets('mobile Scripture chrome avoids overflow at 320 px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer(
      overrides: [
        youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.35),
            ),
            child: ScriptureWorkspace(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('scripture-book-picker')), findsOneWidget);
    expect(find.byKey(const Key('add-scripture-to-journal')), findsOneWidget);
  });

  testWidgets('Scripture workspace scrolls in a short desktop window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ScriptureWorkspace()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Genesis 1'), findsOneWidget);
    expect(find.byKey(const Key('scripture-version-picker')), findsOneWidget);
  });

  testWidgets('desktop phases avoid bottom overflow in a short window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final harness = await _pumpCompletedApp(tester, quietTimeLogging: true);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('binder-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Quiet Time logging'), findsOneWidget);
    expect(find.text('Christian Mode'), findsNothing);
    Navigator.of(tester.element(find.text('Meno settings'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-journal')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await harness.container
        .read(journalControllerProvider.notifier)
        .openMood('2026-09-01');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<_Harness> _pumpCompletedApp(
  WidgetTester tester, {
  bool quietTimeLogging = false,
  TargetPlatform? platform,
}) async {
  final database = FakeDatabaseService();
  const dateKey = '2026-09-01';
  final daily = DayEntry.empty(
    dateKey: dateKey,
    type: DayEntryType.daily,
    now: DateTime(2026, 9, 1, 9),
  ).copyWith(content: 'A thoughtful project launch with the team.');
  await database.saveDayEntry(daily);
  await database.saveCheckIn(
    DailyCheckIn.forDate(dateKey: dateKey, moodAngle: .3, moodIntensity: .7),
  );
  await database.saveSetting(
    DatabaseService.quietTimeLoggingSettingKey,
    '$quietTimeLogging',
  );
  final container = ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(database),
      youVersionBibleProvider.overrideWithValue(_FixtureBibleProvider()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: const EditorScreen(autoInitialize: false),
      ),
    ),
  );
  await tester.pump();
  await container
      .read(journalControllerProvider.notifier)
      .initialize(now: DateTime(2026, 9, 1, 20));
  await tester.pumpAndSettle();
  final harness = _Harness(container, database, daily);
  addTearDown(harness.dispose);
  return harness;
}

class _FixtureBibleProvider extends YouVersionBibleProvider {
  _FixtureBibleProvider() : super(appKey: 'fixture');

  static const version = BibleVersion(
    id: '111',
    abbreviation: 'NIV',
    title: 'New International Version',
    copyright: 'NIV fixture attribution',
  );

  @override
  Future<List<BibleVersion>> versions() async => const [version];

  @override
  Future<List<BibleBook>> books(BibleVersion version) async => const [
    BibleBook('GEN', 'Genesis'),
  ];

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async =>
      const [1];

  @override
  Future<List<BiblePassage>> chapterVerses(
    BibleVersion version,
    BibleBook book,
    int chapter,
  ) async => [
    BiblePassage(
      id: 'GEN.1.1',
      reference: 'Genesis 1:1',
      content: 'In the beginning God created the heavens and the earth.',
      version: version,
    ),
    BiblePassage(
      id: 'GEN.1.2',
      reference: 'Genesis 1:2',
      content: 'Now the earth was formless and empty.',
      version: version,
    ),
    for (var verse = 3; verse <= 24; verse++)
      BiblePassage(
        id: 'GEN.1.$verse',
        reference: 'Genesis 1:$verse',
        content:
            'This longer fixture verse keeps the continuous chapter moving '
            'so scrolling behavior can be exercised reliably.',
        version: version,
      ),
  ];

  @override
  Future<BiblePassage> passage(BibleVersion version, String passageId) async =>
      BiblePassage(
        id: 'GEN.1.1',
        reference: 'Genesis 1:1',
        content: 'In the beginning God created the heavens and the earth.',
        version: version,
      );
}

class _Harness {
  _Harness(this.container, this.database, this.daily);
  final ProviderContainer container;
  final FakeDatabaseService database;
  final DayEntry daily;

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}
