import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/models/journal_entry.dart';
import 'package:meno/providers/journal_providers.dart';
import 'package:meno/services/bible_service.dart';
import 'package:meno/ui/scripture_screen.dart';

void main() {
  testWidgets('expanded mobile reader and multiline selection golden', (
    tester,
  ) async {
    await _pumpReader(tester);

    await tester.tap(find.byKey(const ValueKey('scripture-verse-JHN.3.16')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ScriptureWorkspace),
      matchesGoldenFile('goldens/scripture_mobile_expanded_selection.png'),
    );
  });

  testWidgets('collapsed mobile dock, scroll fade, and range golden', (
    tester,
  ) async {
    await _pumpReader(tester);

    await tester.tap(find.byKey(const ValueKey('scripture-verse-JHN.3.16')));
    await tester.tap(find.byKey(const ValueKey('scripture-verse-JHN.3.17')));
    await tester.drag(
      find.byKey(const Key('scripture-verse-list')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ScriptureWorkspace),
      matchesGoldenFile('goldens/scripture_mobile_collapsed_range.png'),
    );
  });
}

Future<void> _pumpReader(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        youVersionBibleProvider.overrideWithValue(_GoldenBibleProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const ScriptureWorkspace(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _GoldenBibleProvider extends YouVersionBibleProvider {
  _GoldenBibleProvider() : super(appKey: 'fixture');

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
    BibleBook('JHN', 'John'),
  ];

  @override
  Future<List<int>> chapters(BibleVersion version, BibleBook book) async =>
      const [3];

  @override
  Future<List<BiblePassage>> chapterVerses(
    BibleVersion version,
    BibleBook book,
    int chapter,
  ) async => [
    BiblePassage(
      id: 'JHN.3.16',
      reference: 'John 3:16',
      content:
          'For God so loved the world that he gave his one and only Son, '
          'that whoever believes in him shall not perish but have eternal life.',
      version: version,
    ),
    BiblePassage(
      id: 'JHN.3.17',
      reference: 'John 3:17',
      content:
          'For God did not send his Son into the world to condemn the world, '
          'but to save the world through him.',
      version: version,
    ),
    for (var verse = 18; verse <= 32; verse++)
      BiblePassage(
        id: 'JHN.3.$verse',
        reference: 'John 3:$verse',
        content:
            'This reading text continues the chapter with a calm, generous '
            'measure for scrolling and reviewing the refined reader chrome.',
        version: version,
      ),
  ];

  @override
  Future<BiblePassage> passage(BibleVersion version, String passageId) async =>
      BiblePassage(
        id: passageId,
        reference: 'John 3:16',
        content: 'Fixture passage',
        version: version,
      );
}
